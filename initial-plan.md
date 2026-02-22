# Developer Prompt: Implement Auto Display Resolution Detection in Moonlight Qt

---

## Overview and Motivation

You are implementing a new feature for **Moonlight Qt** — the open source PC game streaming client used with NVIDIA GameStream and Sunshine. The feature is: **automatic detection of the client display's native resolution and refresh rate, with the ability to dynamically switch the streaming resolution when the user's display configuration changes** (e.g., when a MacBook is connected to or disconnected from an external 4K monitor).

This is a real-world usability problem that affects a large number of Moonlight users. The typical pain point is a user who alternates between two display setups — say, a MacBook's native 2560×1600 display and an external 4K monitor — and must manually change the streaming resolution in Moonlight's settings every time they switch. The goal is to eliminate that manual step entirely with a new "Match Current Display" (or equivalent) option in the resolution picker.

This feature is being implemented with the intention of submitting it as a **pull request to the official moonlight-stream/moonlight-qt repository on GitHub**. Therefore, code quality, maintainability, cross-platform correctness, and alignment with the project's existing conventions are critically important. You are not just building something that works for one person — you are building something that will serve every Moonlight user on Windows, macOS, and Linux in perpetuity.

---

## Repository Reference

- **Repo:** https://github.com/moonlight-stream/moonlight-qt
- **License:** GPL-3.0
- **Language:** C++ with Qt framework (Qt 6 recommended, Qt 5.12+ also supported)
- **UI layer:** QML (Qt Quick / QtQuickControls2)
- **Build system:** qmake
- **Active platforms:** Windows, macOS, Linux (X11 and Wayland), Steam Link

Clone and set up the repository before beginning:

```bash
git clone https://github.com/moonlight-stream/moonlight-qt.git
cd moonlight-qt
git submodule update --init --recursive
```

Build instructions are in the README. On macOS, Qt can be installed via Homebrew. The build target for development is `make debug` after running `qmake moonlight-qt.pro`.

---

## The GitHub Issue This PR Addresses

**Issue #1678** — "Auto-detect client display specs (resolution/refresh/HDR) and propose matching video mode to Sunshine"  
https://github.com/moonlight-stream/moonlight-qt/issues/1678

This issue was opened on August 27, 2025 and has been assigned to the **v7.0 milestone**, which is a strong positive signal: the maintainer has already triaged this as planned work for the next major version. This means a well-written PR is very likely to be accepted rather than closed as out-of-scope.

**Read the issue in full before writing a single line of code.** The original issue author (GitHub user `blaadje`) has already done useful platform-by-platform API research in the issue body. Their proposed approach maps out the correct platform-native APIs for Windows, macOS, and Linux, which you should use as your starting reference — though you should evaluate them against Qt's cross-platform abstractions (described below) to determine how much platform-specific code is truly necessary.

The issue summary states:

> "Moonlight currently relies on user-configured video modes (e.g., 1920×1080@60) and does not detect the local display's native specs. This leads to suboptimal defaults and manual reconfiguration when users switch monitors or displays."

The desired behavior is:

> "A toggle like 'Match current display' — detect the display where Moonlight is rendered/fullscreened, query its native mode(s): resolution, refresh rate, color space / HDR capability (where available)."

Your implementation should satisfy this description while remaining pragmatic — HDR detection is marked optional in the issue and should be treated as a stretch goal, not a blocker. Focus first on resolution and refresh rate.

---

## Understanding the Lead Maintainer's Style

The lead maintainer is **Cameron Gutman** (GitHub: `cgutman`). Before writing any code, spend time reading recent merged PRs and closed issues to calibrate his preferences. A few things you can infer from the project's history:

- **He values correctness over cleverness.** The codebase is readable and methodical. Do not try to impress with unusual techniques.
- **He cares about cross-platform behavior deeply.** The project runs on Windows, macOS, Linux/X11, Linux/Wayland, and Steam Link. Any change that breaks or degrades any of these targets will not be merged. If your feature cannot be cleanly implemented on a platform, it must gracefully degrade — showing the user the existing manual options rather than crashing or behaving unexpectedly.
- **He prefers minimal surface area for new settings.** Look at how existing preferences are implemented in `streamingpreferences.h` and `streamingpreferences.cpp` — they are clean enums with clear semantics. Don't add five new settings when one will do.
- **He expects existing behavior to be unchanged for existing users.** The default behavior after your change must be identical to the current behavior. The new "auto" mode must be opt-in.
- **He expects code that compiles cleanly with no warnings** on all platforms.
- **PR hygiene matters.** The project uses GitHub PRs with clear descriptions. Look at the format of recent accepted PRs and mirror it. Your PR description should reference issue #1678 explicitly using GitHub's `Closes #1678` syntax so it auto-links.

**Before submitting the PR**, post a comment on issue #1678 describing your intended approach and asking whether the implementation direction looks correct to Cameron. This is standard open source etiquette and avoids the painful scenario of completing a 500-line implementation only to have it rejected for an architectural reason that could have been caught in a 3-sentence comment. Keep the comment concise and technical — describe which files you plan to touch, what new enum value or preference you plan to add, and roughly how you'll handle each platform.

---

## Key Source Files to Understand First

Before writing any code, read and understand these files thoroughly:

### `app/settings/streamingpreferences.h`
This is the central preferences class exposed to QML. It contains enums for all user-configurable options. Resolution and FPS are stored as plain `int` members (`width`, `height`, `fps`). You will likely need to add a new enum here — something like:

```cpp
enum ResolutionMode {
    RM_MANUAL,        // existing behavior, user picks resolution explicitly
    RM_MATCH_DISPLAY  // new: read from active display at stream start
};
Q_ENUM(ResolutionMode)
```

And a corresponding property:
```cpp
Q_PROPERTY(ResolutionMode resolutionMode ...)
```

Study exactly how existing enum preferences (like `VideoCodecConfig`, `WindowMode`, `VideoDecoderSelection`) are declared, stored, loaded, and saved. Your new preference must follow the same pattern exactly — same use of `QSettings`, same default value handling, same `Q_PROPERTY` + `Q_ENUM` pattern for QML exposure.

### `app/settings/streamingpreferences.cpp`
This is where preferences are loaded from and saved to persistent storage (via `QSettings`). Look at how existing settings are read with default fallbacks. Your new `resolutionMode` preference must be serialized/deserialized here.

### `app/gui/SettingsView.qml`
This is the main settings UI. The resolution picker is a `ComboBox` (`resolutionComboBox`) populated from a `ListModel`. You need to add a new entry to this list model — something like `"Match current display (auto)"` — and wire it to the new `RM_MATCH_DISPLAY` enum value. Study how the existing entries are set up and how the combo box selection maps to `StreamingPreferences.width` and `StreamingPreferences.height`. When "auto" is selected, you should NOT write a specific width/height to the preferences — those fields become irrelevant and should be grayed out or hidden in the UI.

### `app/streaming/session.cpp` and `session.h`
This is where a streaming session is actually started. This is likely where you will read the active display resolution at stream-launch time if `RM_MATCH_DISPLAY` is set. Look at how `StreamingPreferences` fields are consumed here to configure the stream parameters. This is where the `width` and `height` values are ultimately passed into the streaming negotiation — your task is to intercept that moment and substitute the live display resolution when the auto mode is active.

### `app/gui/main.qml` and the main window infrastructure
Understand how the main application window relates to the Qt screen stack. `QGuiApplication::primaryScreen()` and the `QScreen` class are your friends here. Specifically, `QScreen::size()` returns the screen's geometry in logical pixels, and `QScreen::nativeOrientation()` + `QScreen::physicalDotsPerInch()` can help you find the actual hardware resolution. On high-DPI displays (like Retina MacBooks), you will need `QScreen::devicePixelRatio()` to convert from logical to physical pixels — this is a common pitfall and must be handled correctly.

---

## Technical Implementation Plan

### Step 1: Add the new preference

In `streamingpreferences.h`, add the `ResolutionMode` enum and property as described above. In `streamingpreferences.cpp`, add load/save logic for it using `QSettings`, defaulting to `RM_MANUAL` so existing users see no change.

### Step 2: Update the settings UI

In `SettingsView.qml`, add "Match current display (auto)" as a new entry in `resolutionListModel`. When this entry is selected, the `video_width` and `video_height` fields shown in any custom entry UI should be hidden or disabled — they are meaningless in auto mode. Wire the selection to set `StreamingPreferences.resolutionMode` rather than `StreamingPreferences.width/height`.

Also update the FPS combo box behavior: when in auto mode, FPS should ideally also be read from the display's refresh rate, or at minimum should remain user-configurable with a clear label indicating this.

### Step 3: Implement display resolution reading

Create a new utility function (or small helper class) — something like `DisplayUtils::getNativeResolutionForWindow(QWindow*)` — that returns the physical pixel resolution and refresh rate of the display containing a given window.

**Use Qt's `QScreen` API as your primary tool.** `QWindow::screen()` returns the screen the window is currently on. `QScreen::size()` × `QScreen::devicePixelRatio()` gives you the native pixel resolution. `QScreen::refreshRate()` gives you the refresh rate. This approach is cross-platform and avoids most platform-specific code.

However, Qt's `QScreen` API can sometimes return logical rather than physical dimensions on certain platforms (particularly Wayland compositors and some Windows configurations). The issue author's platform-specific suggestions are worth implementing as fallbacks:

- **Windows:** `EnumDisplaySettings` or `DXGI` via `IDXGIOutput::GetDisplayModeList` to get the exact hardware mode. Use `MonitorFromWindow` to identify which monitor the window is on.
- **macOS:** `CGDisplayCopyDisplayMode` via CoreGraphics gives the exact hardware resolution including HiDPI modes. Wrap this in an `#ifdef Q_OS_MACOS` block.
- **Linux/X11:** XRandR via `XRRGetScreenResources` + `XRRGetCrtcInfo`.
- **Linux/Wayland:** Qt's `QScreen` should be sufficient here as Wayland compositors generally report correct logical sizes; physical size retrieval is compositor-dependent.

For the Steam Link embedded target, the QScreen approach should work without platform-specific code since it runs a single fixed display.

Structure this so the Qt-native path runs first, with platform-specific paths as an override or verification layer. Do not write platform-specific code where the Qt API is demonstrably correct.

### Step 4: Hook into session startup

In `session.cpp`, at the point where `width` and `height` are read from `StreamingPreferences` to configure the stream, add a check:

```cpp
if (prefs->resolutionMode == StreamingPreferences::RM_MATCH_DISPLAY) {
    QSize nativeRes = DisplayUtils::getNativeResolutionForWindow(m_Window);
    width = nativeRes.width();
    height = nativeRes.height();
    // also update fps from screen refresh rate if desired
}
```

You need access to a `QWindow*` at this point. Verify that `session.cpp` has access to the main window or streaming window object at the time the session parameters are configured. If not, you may need to pass it in or use `QGuiApplication::primaryScreen()` as a reasonable fallback (understanding that this may be wrong if the user has moved Moonlight to a secondary screen — document this limitation).

### Step 5: Handle display change events

This is the differentiating feature — not just reading the resolution once, but **automatically updating the resolution when the user's display configuration changes** (e.g., plugging in or unplugging an external monitor).

`QScreen` emits several useful signals:
- `QGuiApplication::screenAdded(QScreen*)` — fired when a new display is connected
- `QGuiApplication::screenRemoved(QScreen*)` — fired when a display is disconnected
- `QWindow::screenChanged(QScreen*)` — fired when a window moves to a different screen

When `RM_MATCH_DISPLAY` is active and a display change is detected **while Moonlight is open but not streaming**, update the internally-cached resolution that will be used on next stream launch. You do not need to (and should not attempt to) renegotiate an in-progress stream — that is complex and fragile. Simply ensure that the next stream launch uses the correct current resolution.

You may also want to surface this to the user via the settings UI: when in auto mode, display a read-only text field showing something like "Currently detected: 3840×2160 @ 120Hz" that updates live as displays are connected/disconnected. This is a nice-to-have, not a requirement for the initial PR.

### Step 6: Graceful degradation

If the display resolution cannot be determined (e.g., on an unsupported platform, or if the relevant APIs return zero), fall back to the user's last manually configured resolution and log a warning. Never crash, never freeze, never silently stream at the wrong resolution without indication.

---

## What Not to Do

- **Do not remove or change the behavior of the existing manual resolution picker.** All existing presets (720p, 1080p, 1440p, 4K, custom) must continue to work exactly as before. You are adding a new option, not replacing existing ones.
- **Do not make "Match current display" the default.** Existing users must see zero behavior change after updating.
- **Do not add platform-specific code where Qt's cross-platform API is sufficient.** The codebase is clean and cross-platform; keep it that way.
- **Do not attempt to change the resolution of an in-progress stream.** This is out of scope for this PR. The feature applies at stream-launch time only.
- **Do not hardcode any assumptions about what "native resolution" means on HiDPI screens.** Always use `devicePixelRatio()` to convert logical to physical pixels.
- **Do not add dependencies.** The project's dependency footprint is intentionally minimal. Platform APIs used (CoreGraphics, Win32, XRandR) are already available on their respective platforms without new library dependencies.

---

## Testing Checklist

Before submitting the PR, verify each of the following manually:

- [ ] On **macOS with external 4K display connected**: auto mode selects 3840×2160
- [ ] On **macOS without external display (MacBook native)**: auto mode selects the MacBook's native resolution correctly (e.g., 2560×1600 on a 14" M-series), with `devicePixelRatio` correctly applied
- [ ] On **macOS**: disconnecting the external display while Moonlight is open updates the detected resolution before the next stream launch
- [ ] On **Windows** with a 1080p monitor: auto mode selects 1920×1080
- [ ] On **Windows** with a 4K monitor at 120Hz: auto mode selects 3840×2160 @ 120Hz
- [ ] On **Linux/X11**: correct resolution detected
- [ ] On **Linux/Wayland**: correct resolution detected, or graceful fallback
- [ ] **Existing presets unchanged**: 1080p, 1440p, 4K manual presets work exactly as before
- [ ] **Upgrade scenario**: user upgrading from prior version sees RM_MANUAL as their active mode (no behavior change)
- [ ] **Clean build with no warnings** on all platforms (at minimum, macOS and Windows)
- [ ] **No crash or hang** when `QScreen` APIs return unexpected values

---

## PR Submission Guidance

When you open the pull request:

1. **Title should be clear and specific:** e.g., "Add 'Match current display' auto-resolution mode"
2. **Reference the issue:** Include `Closes #1678` in the PR body
3. **Describe what you changed and why** each decision was made — maintainers shouldn't have to guess
4. **Describe your testing:** which platforms you tested on, what display configurations, what results you observed
5. **Keep the diff focused:** do not bundle unrelated fixes or cleanup into this PR
6. **Be responsive to review feedback:** Cameron may request changes. Engage constructively and quickly.

If the PR is large (likely 300–600 lines across multiple files), consider opening it as a **draft PR** first, posting a comment on issue #1678 linking to the draft and asking for early feedback before the implementation is complete. This prevents wasted work if the architecture needs to change.

---

## Additional Context: The Ecosystem

Moonlight works with two host-side streaming servers:
- **NVIDIA GeForce Experience (GameStream)** — legacy, being deprecated by NVIDIA
- **Sunshine** — the modern open-source alternative, now the recommended host

The Sunshine host already supports matching its resolution to whatever the client requests (via its "Use resolution provided by the client" setting). This means the Windows PC side of the problem is largely already solved — if Moonlight sends the correct resolution in the stream negotiation, Sunshine will match it on the host. Your feature on the client side is the missing piece that completes the loop.

This context matters because it means the feature has real end-to-end value: user connects MacBook to 4K display → Moonlight detects 3840×2160 → sends that to Sunshine → Windows PC switches to 4K → user disconnects external display → Moonlight detects 2560×1600 → next stream launches at MacBook native resolution → Windows PC switches back. The entire workflow becomes zero-friction.

---

## Summary of Files You Will Likely Touch

| File | Change |
|------|--------|
| `app/settings/streamingpreferences.h` | Add `ResolutionMode` enum and property |
| `app/settings/streamingpreferences.cpp` | Add load/save logic for `resolutionMode` |
| `app/gui/SettingsView.qml` | Add "Match current display" option to resolution ComboBox |
| `app/streaming/session.cpp` | Read live display resolution when `RM_MATCH_DISPLAY` is set |
| `app/utils/displayutils.h` (new) | Declare `getNativeResolutionForWindow()` utility |
| `app/utils/displayutils.cpp` (new) | Implement cross-platform display resolution detection |
| `moonlight-qt.pro` | Add new source files to build |

Good luck. This is a well-scoped, high-value feature with active maintainer support — the milestone assignment to v7.0 is a clear green light. Take the time to do it properly.