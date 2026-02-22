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

Ran a CoreGraphics test (`test_display_detection.m`) using the same API path Moonlight uses on macOS. Results on this MacBook Pro (M-series, notched):

```
Found 1 active display(s)

Display 0 (Built-in):
  NATIVE mode found: 3456x2234 @ 120.0 Hz
  Safe area (notch) mode: 3456x2160
  Max refresh at native res: 120.0 Hz
```

The existing detection correctly identifies native resolution, refresh rate, and notch safe area. The current mode reports logical pixels (1728x1117) but `kDisplayModeNativeFlag` correctly points to the full physical resolution. This confirms `StreamUtils::getNativeDesktopMode()` will produce correct results for the proposed feature.

---

## Proposed Approach

1. **Add `ResolutionMode` enum** to `StreamingPreferences` (`RM_MANUAL` / `RM_MATCH_DISPLAY`), persisted via `QSettings`, defaulting to `RM_MANUAL`
2. **Add "Match current display" entry** to the resolution ComboBox in `SettingsView.qml`; disable/grey out W x H fields when selected
3. **In `Session::initialize()`**, when `RM_MATCH_DISPLAY` is set, resolve the display the window is on (reuse existing Qt-to-SDL mapping from `getWindowDimensions()`), call `getNativeDesktopMode()` for that display, and use the result for `m_StreamConfig.width/height` and refresh rate for `m_StreamConfig.fps`

**Files touched:**
- `app/settings/streamingpreferences.h` — new enum + Q_PROPERTY
- `app/settings/streamingpreferences.cpp` — QSettings load/save
- `app/gui/SettingsView.qml` — new combo entry
- `app/streaming/session.cpp` — dynamic resolution at launch

**No new files or dependencies.** The existing cross-platform detection already handles macOS Retina/notch, Windows DPI, and Wayland scaling.

---

## Suggested Comment for Issue #1678

Post this at: **https://github.com/moonlight-stream/moonlight-qt/issues/1678**

> I'd like to take a crack at this. Here's my proposed approach after reading the codebase:
>
> Moonlight already detects native display resolutions via `StreamUtils::getNativeDesktopMode()` (CoreGraphics on macOS, SDL desktop mode on Windows/Linux/Wayland) and presents them as selectable "Native" entries in the resolution picker. The gap is that selecting a native resolution saves a fixed W x H, so switching displays requires manually re-selecting. I'd add a `ResolutionMode` preference (`RM_MANUAL` / `RM_MATCH_DISPLAY`, defaulting to `RM_MANUAL`) and a new "Match current display" entry in the resolution ComboBox. When `RM_MATCH_DISPLAY` is set, `Session::initialize()` would resolve the display the Moonlight window is on -- reusing the existing Qt-to-SDL display mapping in `getWindowDimensions()` -- and call `getNativeDesktopMode()` to get the native resolution for the stream config instead of using saved W/H values. The refresh rate would similarly be read from the matched display.
>
> Files touched: `streamingpreferences.h/.cpp` (new enum + QSettings persistence), `SettingsView.qml` (new combo entry, disable W/H when auto), `session.cpp` (dynamic resolution at launch). No new files or dependencies -- the existing cross-platform detection infrastructure handles macOS Retina/notch, Windows DPI, and Wayland scaling correctly already.
>
> Does this direction look right before I start on the implementation?
