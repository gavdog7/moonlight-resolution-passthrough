# Issue #1678 Investigation: Auto-Detect Client Display Resolution

**Issue:** https://github.com/moonlight-stream/moonlight-qt/issues/1678
**Milestone:** v7.0
**Comment target:** https://github.com/moonlight-stream/moonlight-qt/issues/1678

---

## Investigation Summary

### What the issue asks for

A "Match current display" option that automatically uses the client display's native resolution and refresh rate when launching a stream, so users who switch between displays (e.g. MacBook screen vs external 4K monitor) don't have to manually change resolution settings every time.

### What the codebase already has

After reading through the moonlight-qt source, the existing infrastructure covers ~90% of what's needed:

1. **`StreamUtils::getNativeDesktopMode(displayIndex, &mode, &safeArea)`** (`app/streaming/streamutils.cpp:216`)
   - Already detects native resolution per-display on every platform
   - **macOS:** Uses CoreGraphics `CGDisplayCopyAllDisplayModes` + `kDisplayModeNativeFlag` (correctly handles Retina/HiDPI and notch safe areas on ARM64 Macs)
   - **Windows:** Uses `SDL_GetDesktopDisplayMode()` which returns real hardware resolution even with DPI scaling
   - **Linux/Wayland:** Uses `SDL_GetDisplayMode(displayIndex, 0, mode)` to get native resolution without scaling
   - **Linux/X11:** Uses `SDL_GetDesktopDisplayMode()`

2. **`SystemProperties::refreshDisplays()`** (`app/backend/systemproperties.cpp:218`)
   - Enumerates all connected displays via SDL
   - Stores native resolutions in `monitorNativeResolutions`, safe area in `monitorSafeAreaResolutions`, refresh rates in `monitorRefreshRates`
   - Exposed to QML via `getNativeResolution(displayIndex)`, `getSafeAreaResolution(displayIndex)`, `getRefreshRate(displayIndex)`

3. **`Session::getWindowDimensions()`** (`app/streaming/session.cpp:1313`)
   - Already maps the Qt window's screen to an SDL display index by matching `QScreen::geometry()` coordinates to `SDL_GetDisplayBounds()`
   - This is exactly the logic needed to know *which* display the Moonlight window is on

4. **`SettingsView.qml`** (`app/gui/SettingsView.qml:166`)
   - Already dynamically adds "Native (WxH)" and "Native (Excluding Notch) (WxH)" entries to the resolution ComboBox per connected display

### What's missing (the gap)

When a user selects "Native (3456x2234)" today, the resolution gets **saved as a fixed `width=3456, height=2234`** in `QSettings`. If the user later connects to a different display, the saved value is stale and they must manually re-select.

The feature needs:
- A way to persist "use native resolution" as a *mode* rather than a fixed W x H
- At stream-launch time, dynamically resolve the actual resolution based on the current display
- Default to manual mode so existing users see no change

### Where the stream config is set

In `Session::initialize()` (`session.cpp:635-637`):
```cpp
LiInitializeStreamConfiguration(&m_StreamConfig);
m_StreamConfig.width = m_Preferences->width;
m_StreamConfig.height = m_Preferences->height;
```

This is the interception point. When in auto mode, instead of reading saved `width`/`height`, we'd resolve the current display's native resolution here using the existing APIs.

---

## Local Validation

Ran a CoreGraphics test (`test_display_detection.m`) using the same API path and notch-detection heuristic Moonlight uses on macOS (verified identical to `streamutils.cpp:266`). Results on this MacBook Pro (M-series, notched):

```
--- Display 0 (ID: 1) ---
  Built-in: YES
  Current mode: 1728x1117 @ 120.0 Hz (native flag: NO)
  Total modes available: 29
  >> NATIVE mode found: 3456x2234 @ 120.0 Hz
  >> Safe area (notch) mode: 3456x2160
  Max refresh at native res: 120.0 Hz
```

The existing detection correctly identifies native resolution, refresh rate, and notch safe area. The current mode reports logical pixels (1728x1117) but `kDisplayModeNativeFlag` correctly points to the full physical resolution. This confirms `StreamUtils::getNativeDesktopMode()` will produce correct results for the proposed feature.

**Note:** The notch safe-area heuristic (`nativeH <= modeH + 100`) could theoretically match modes *taller* than native, not just shorter. In practice this doesn't happen because no display mode exceeds the native resolution height, but it's worth being aware of when reviewing Moonlight's detection logic.

---

## Proposed Approach

1. **Add `ResolutionMode` enum** to `StreamingPreferences` (`RM_MANUAL` / `RM_MATCH_DISPLAY`), persisted via `QSettings` under a new key (e.g. `resolutionmode`), defaulting to `RM_MANUAL` so existing users see no change
2. **Add "Match current display" entry** to the resolution ComboBox in `SettingsView.qml`; disable/grey out W x H fields when selected
3. **In `Session::initialize()`**, when `RM_MATCH_DISPLAY` is set, resolve the display the window is on (reuse existing Qt-to-SDL mapping from `getWindowDimensions()`), call `getNativeDesktopMode()` for that display, and use the result for `m_StreamConfig.width/height`

**Files touched:**
- `app/settings/streamingpreferences.h` — new enum + Q_PROPERTY
- `app/settings/streamingpreferences.cpp` — QSettings load/save (new `resolutionmode` key, backward-compatible: absent key = `RM_MANUAL`)
- `app/gui/SettingsView.qml` — new combo entry
- `app/streaming/session.cpp` — dynamic resolution at launch

**No new files or dependencies.** The existing cross-platform detection already handles macOS Retina/notch, Windows DPI, and Wayland scaling.

---

## Scoping Decisions and Edge Cases

### Refresh rate: resolution only, not FPS (v1)

The FPS setting (`m_StreamConfig.fps`) is a separate user preference with its own ComboBox and is conceptually distinct from resolution — users often want a specific FPS regardless of what their display supports (e.g. capping at 60fps for a weaker host GPU even on a 120Hz client display). For v1, `RM_MATCH_DISPLAY` overrides **resolution only**. The user's existing FPS preference is left untouched.

A follow-up `RM_MATCH_DISPLAY_AND_FPS` mode could be added later if there's demand, but coupling resolution and FPS auto-detection in v1 risks confusing cases where the host can't sustain the client's native refresh rate.

### Which display: resolved at stream-launch time, after fullscreen transition

`getWindowDimensions()` maps the Qt window to an SDL display index by matching `QScreen::geometry()` coordinates to `SDL_GetDisplayBounds()`. Key behaviors to be aware of:

- **Window spanning two displays:** SDL picks the display with the largest overlap area. This is reasonable default behavior and matches what users would expect.
- **Fullscreen display targeting:** Moonlight has a "Fullscreen display" setting that can target a different display than the one the window is currently on. Resolution must be resolved **after** the fullscreen target is determined, not before. In `Session::initialize()`, the fullscreen display index is already known at the point where `m_StreamConfig.width/height` is set, so we use that index rather than the pre-fullscreen window position. This avoids the scenario where resolution is detected for display A but the stream launches fullscreen on display B.
- **Fallback:** If `getWindowDimensions()` can't match any SDL display to the Qt screen coordinates, it falls back to display index 0. This is acceptable for `RM_MATCH_DISPLAY` — the user still gets a native resolution, just potentially for the wrong display in an edge case that's unlikely in practice (it would require SDL and Qt to disagree about display geometry).

### Host-side resolution validation

Not all resolutions are accepted by the streaming host (NVIDIA GameStream / Sunshine). Non-standard resolutions like 3456x2234 may be rejected or silently rounded. This is an **existing limitation** that also affects today's manual "Native (WxH)" selection — it's not new to this feature. However, auto-detection makes it more visible since users won't see the selected resolution before streaming starts.

Mitigation options (to discuss with maintainer):
- **Log the resolved resolution** so users can diagnose stream failures
- **Show a brief toast/indicator** of the auto-detected resolution before or during stream launch
- Accept the existing behavior for v1, since manual "Native" selection already has the same limitation and users of non-standard displays are accustomed to it

This is worth raising in the issue comment so the maintainer can decide on the desired UX.

---

## Suggested Comment for Issue #1678

Post this at: **https://github.com/moonlight-stream/moonlight-qt/issues/1678**

> I'd like to take a crack at this. Here's my proposed approach after reading the codebase:
>
> Moonlight already detects native display resolutions via `StreamUtils::getNativeDesktopMode()` (CoreGraphics on macOS, SDL desktop mode on Windows/Linux/Wayland) and presents them as selectable "Native" entries in the resolution picker. The gap is that selecting a native resolution saves a fixed W x H, so switching displays requires manually re-selecting. I'd add a `ResolutionMode` preference (`RM_MANUAL` / `RM_MATCH_DISPLAY`, defaulting to `RM_MANUAL`) and a new "Match current display" entry in the resolution ComboBox. When `RM_MATCH_DISPLAY` is set, `Session::initialize()` would resolve the display the Moonlight window is on -- reusing the existing Qt-to-SDL display mapping in `getWindowDimensions()` -- and call `getNativeDesktopMode()` to get the native resolution for the stream config instead of using saved W/H values.
>
> A few scoping notes:
> - **Resolution only, not FPS (v1):** The FPS setting is a separate preference and users often want a specific FPS regardless of display capability (e.g. capping at 60 for a weaker host). I'd leave the FPS preference untouched and only auto-detect resolution. A combined mode could be added later if there's demand.
> - **Fullscreen display targeting:** Resolution would be resolved using the fullscreen target display index (already known at the `m_StreamConfig` assignment point in `Session::initialize()`), not the pre-fullscreen window position, so multi-monitor setups get the right resolution.
> - **Host-side resolution limits:** Non-standard native resolutions (e.g. 3456x2234) may not be accepted by all GameStream/Sunshine hosts. This is an existing limitation of the manual "Native" selection too, but auto-detection makes it less visible. Would it be worth logging the resolved resolution or showing a brief indicator, or is the current behavior acceptable?
>
> Files touched: `streamingpreferences.h/.cpp` (new enum + QSettings persistence), `SettingsView.qml` (new combo entry, disable W/H when auto), `session.cpp` (dynamic resolution at launch). No new files or dependencies -- the existing cross-platform detection infrastructure handles macOS Retina/notch, Windows DPI, and Wayland scaling correctly already.
>
> Does this direction look right before I start on the implementation?
