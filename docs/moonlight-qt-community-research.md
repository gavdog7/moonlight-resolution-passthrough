# Moonlight Qt Community Research

Notes from studying the moonlight-stream/moonlight-qt project to understand the community before contributing.

---

## Project Overview

Moonlight is an open-source game streaming client that implements the NVIDIA GameStream protocol. The Qt version is the primary desktop client (macOS, Windows, Linux). It was originally created as "Limelight" by six Case Western Reserve University students at the MHacks hackathon in 2013.

**Repo:** https://github.com/moonlight-stream/moonlight-qt
**License:** GPL-3.0
**Stars:** ~4.5k

---

## Contributor Profile

### The project is effectively a solo effort

Out of the most recent 100 commits, **99 are by cgutman (Cameron Gutman)**. He has 2,768 total commits — roughly 97% of the entire codebase.

| Contributor | Commits | Type of Contribution |
|---|---|---|
| cgutman | 2,768 | All core code, architecture, features |
| raidancampbell | 41 | Co-founder, early Qt UI work (2018, now inactive) |
| jorys-paulin | 40 | French translations (Weblate), community tooling |
| Kaitul | 17 | Traditional Chinese translations (Weblate) |
| hectorssr | 10 | Spanish translations (Weblate) |

Cameron commits directly to main — he only opened 4 PRs in the entire history. He is the sole code decision-maker.

### Who is cgutman

- CWRU alumnus, co-founded Moonlight at MHacks 2013
- Deep systems-level developer: streaming protocols, video codecs, SDL, FFmpeg
- Contributor to ReactOS (granted commit access for networking work)
- His Android apps (Moonlight, Remote ADB Shell) have 5M+ installs combined
- Bio: "Moonlighting on @moonlight-stream"

---

## How External Contributions Are Handled

### What gets merged

- Small, clean changes that fit existing patterns
- Translations (via Weblate)
- Dependency bumps (dependabot)
- Minor fixes and docs/metadata cleanups

### What doesn't get merged

Larger feature PRs from external contributors have a very low merge rate. Many sit open indefinitely with zero comments. Examples of unmerged PRs:
- Spatial audio support (#1803)
- Stylus/tablet passthrough (#1799)
- HDR fixes (#1763, #1765)
- HTTP wake support (#1770)
- Client-side cursor (#1785)
- Profile support (#1780)

### AI-authored PRs are silently ignored

There's no explicit policy, but the pattern is clear — PRs flagged as AI-generated receive zero engagement:
- PR #1768 (tagged Claude Code): 0 comments, months of silence
- PR #1777 (stated Claude Code assistance): 0 comments, weeks of silence
- PR #1803 (ChatGPT-style summary): called out as "AI slop" by another contributor, closed same day

Meanwhile, human contributions like a Docker README addition (#1791) get "Merged, thanks!" within days.

There is no CONTRIBUTING.md, no `.cursorrules`, no `.claude` config in the repo.

---

## Contribution Strategy

Given the above, a successful contribution to this project needs to:

1. **Start with discussion, not code.** Comment on the issue with a concrete proposal and ask if the direction looks right. Respect that Cameron may already have his own plan.
2. **Keep the diff minimal.** Match existing code style exactly, don't refactor surrounding code, don't add unnecessary abstractions.
3. **Make it opt-in.** New features should not change default behavior for existing users.
4. **Be patient and responsive.** Solo maintainers review on their own schedule. If feedback comes, respond quickly.
5. **Demonstrate genuine understanding of the codebase.** The strongest signal is showing you've read the code and understand existing patterns — not just proposing an idea.

---

## Target Feature: Auto Display Resolution Detection (Issue #1678)

Issue #1678 requests a "Match current display" mode that auto-detects the client display's native resolution at stream launch time. It's milestoned for v7.0.

### Key finding: ~90% of the infrastructure already exists

- `StreamUtils::getNativeDesktopMode()` detects native resolution per-display on every platform
- `SystemProperties::refreshDisplays()` enumerates displays and exposes native resolutions to QML
- `Session::getWindowDimensions()` maps the Qt window to an SDL display index
- The resolution ComboBox already shows per-display "Native (WxH)" entries

### The gap

Selecting "Native" today saves a fixed WxH. Switching displays requires manual re-selection. The feature needs a persisted resolution *mode* that dynamically resolves at stream launch.

### Proposed approach

- New `ResolutionMode` enum in `StreamingPreferences` (manual vs match-display, defaulting to manual)
- New "Match current display" combo entry in `SettingsView.qml`
- Dynamic resolution in `Session::initialize()` using existing detection APIs
- Resolution only (not FPS) for v1 — FPS is a separate user preference
- 4 files touched, no new files or dependencies
