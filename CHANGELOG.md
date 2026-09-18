# Changelog

All notable changes to RedTrace for macOS are documented here.

## 3.0.0 — 2026-09-18

### Added

- Native PTY-backed interactive Runner sessions so terminal-aware programs receive a real terminal.
- Terminal rendering for direct keyboard input, paste, terminal resizing, ANSI styles, alternate-screen behavior, cursor visibility, bracketed paste, and basic terminal query responses.
- ChatGPT activity view with structured local hook records for tool start/finish events, command inputs, output, exit status, and errors.
- ChatGPT terminology throughout the interface, replacing the older Codex-facing label.
- Dedicated workspace views for Watch, Run, ChatGPT, and BTOP; responsive Tabs and Cards layouts; menu-bar quick panel; and local background operation.
- Watch-source selection, common command insertion menus, customizable red-and-black appearance, always-on-top, and live CPU/GPU/RAM monitoring.

### Changed

- Runner shells now use a real PTY instead of the `script` wrapper. This improves compatibility with TTY-aware installers, `sudo`, progress interfaces, and interactive tools.
- Hooks preserve non-command tool events and serialize target/input/exit/error fields where available.
- Main README rewritten to match the Windows project, with clearer install, privacy, and capability guidance.

### Fixed

- Resolved native terminal and ChatGPT activity-view compilation issues.
- Added macOS build validation in GitHub Actions.
- Kept standard terminal output handling separate from the old `NO_COLOR`/forced color behavior.

## Earlier releases

- **2.6.2:** independently show or hide Watch, Run, ChatGPT/Codex, and BTOP cards.
- **2.6.1:** added automatic and manual BTOP card column choices.
- **2.6:** added categorized Common Commands menus to every Runner.
- **2.5–2.5.2:** introduced responsive Cards mode and fixed fitting/column behavior.
- **2.4:** added menu-bar background operation and cleanup of stale Watch sessions.
- **2.3–2.3.1:** added movable, resizable BTOP cards and fixed gesture conflicts.
- **2.2–2.2.1:** established the RedTrace red-and-black theme and dedicated windows.
- **2.1:** added the native BTOP system-monitor view.
- **1.0–1.7:** introduced smoother rendering, 60 Hz updates, virtual-terminal screen handling, Watch/Runner tabs, source selection, and the original local command-activity bridge.
