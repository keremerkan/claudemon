# Changelog

All notable changes to this project will be documented in this file.

## [1.5.0] - 2026-11-19

Claudemon has a new maintainer: the repository moved to
[keremerkan/claudemon](https://github.com/keremerkan/claudemon) and the app is
now signed by AKE Software GmbH.

### Added

- Accounts without a session limit (Max plans no longer have one) are
  detected from Claude Code's output: the session limit is hidden and a weekly
  limit takes its place. A **Main limit** setting chooses which weekly limit
  the menu bar shows first, and in the bar graph a **Second bar** option
  (on by default) shows the other one.
- **Show remaining** setting: every number, bar, ring and gauge counts down
  from 100% (what's left) instead of up from 0%. Colors still follow usage.
- **Claude Usage Rings**, a new medium desktop widget with the floating
  window's layout: a ring for every limit.
- A new Liquid Glass app icon.

### Changed

- The floating window shows a ring for every limit instead of one ring and
  bars; its footer is centered.
- The small desktop widget shows only the main limit's ring.
- The desktop widgets say "updated HH:mm" (and "last update HH:mm" in orange
  when the latest fetch failed), matching the floating window.
- Reset countdowns of a day or more show days: "resets in 6d 21h 53m".
- The gauge icon in the menu bar, the panel header and the medium widget
  follows the main limit, in five steps instead of three.
- The "Claude Code isn't installed" screen shows the current installer
  command (`curl -fsSL https://claude.ai/install.sh | bash`) and links to the
  setup guide for other ways to install.
- Homebrew: the cask moved to `keremerkan/tap`. Install with
  `brew install --cask keremerkan/tap/claudemon`.

### Fixed

- The menu bar showed "—" instead of usage when there was no session limit.
- The limit-reset alert for a session fired only when the next session
  started, not when the window ended.
- Usage tips in newer Claude Code output could be misread as a usage limit.
- A usage check could hang for good if a process Claude Code started kept its
  output open; it now times out and retries.
- "100%" touched the ring in the small widget and the floating window.
- After a failed check, the widget showed the time of the failure as its
  "last update" time instead of when the shown data was captured.
- Around a reset, the countdown could briefly show about 8760 hours.
- A usage check interrupted by sleep could apply its late result after wake,
  briefly showing an error or letting two checks run at once.
- When Claude Code is in none of the usual install locations, finding it
  through your shell now also reads `.zshrc` / `.bashrc`, and gives up after
  10 seconds instead of stalling usage checks when a startup file hangs.

### Upgrade notes

- The new signature uses a new shared container, so **Precise bar fill**
  starts off; turn it on again in Settings if you used it.
- macOS may ask you to approve **Launch at login** again in System Settings →
  General → Login Items.
- If a desktop widget shows "Open Claudemon", open the app once.

### Maintenance

- Swift 6 language mode with `@Observable` models; the tests moved to Swift
  Testing.
- The Xcode project is maintained by hand (XcodeGen removed); version and
  build are set per target, and the release script checks that the app and
  widget versions match.
- Dead code and duplication removed across the app, the widget and the tests;
  the unused `build-app.sh` and `build-xcode.sh` scripts are gone, and the
  widget cache no longer stores an error message and write time nothing read.

## [1.4.7] - 2026-09-10

### Added

- Bar graph style: the **Weekly bar** now has a source picker, so the second
  bar can track either **Current Week (all models)** or the per-model weekly
  limit (shown under its current model name, e.g. Fable). Defaults to all
  models, so existing setups look the same.
- Right-click (or control-click) the menu bar item, in any style, for a
  Refresh / Quit context menu without opening the panel.

## [1.4.6] - 2026-07-09

### Added

- Limit-reset alert: when a session/weekly limit you actually used rolls over
  into a fresh window while the app is running, Claudemon posts a single
  notification that the quota is available again. Untouched windows reset
  silently. Toggleable via the new "When a limit resets" setting (default on).
  Thanks @anilsenay!

### Fixed

- Avoided force-unwrapping static update/download URLs so invalid URL construction fails gracefully instead of crashing.
- Corrected the privacy documentation to disclose the GitHub Releases update check while clarifying that usage data remains local and telemetry-free.

### Maintenance

- Ignored local `.wrongstack/` session artifacts in Git.
