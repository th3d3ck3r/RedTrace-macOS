# Changelog

## 2.7.0
- Native `forkpty` Runner, interactive keyboard/paste input, resize propagation, terminal styles, alternate screen, bracketed paste, cursor visibility, and terminal replies.
- ChatGPT replaces CODEX in the UI; Minimal, Normal, and Verbose observable-activity views share one bounded local store.
- Hooks preserve non-command tool events and record target, input, exit code, and error metadata.

## 2.6.2
- Cards can independently show or hide WATCH, RUN, CODEX, and BTOP panes.

## 2.6.1
- BTOP cards gained AUTO and one-to-four column layouts.

## 2.6.0
- Added categorized Common Commands menus to Runner windows and cards.

## 2.5.2
- Separated card auto-fit height from column selection.

## 2.5.1
- Added responsive Card auto-fit sizing.

## 2.5.0
- Added tabs/cards layouts, draggable and resizable cards, and dedicated-window controls.

## 2.4.0
- Added menu-bar operation and live external-shell session management.

## 2.3.1
- Prevented window dragging from stealing BTOP card gestures.

## 2.3.0
- Added movable/resizable BTOP metric cards and recoverable toolbar controls.

## 2.2.1
- Introduced the red-on-black default theme and 85% default opacity.

## 2.2.0
- Added dedicated WATCH, RUN, CODEX, and BTOP windows.

## 2.1.0
- Added the built-in BTOP system-monitor tab.

## 2.0.3
- Replaced shell-wide redirection with pseudo-terminal external shell capture.

## 2.0.2
- Added the native RedTrace icon.

## 2.0.1
- Replaced unreliable SwiftUI color pickers with native color wells.

## 2.0.0
- Renamed CommandGlass to RedTrace and migrated its integrations.

## 1.7.0
- Added CODEX command activity and local/remote labels.

## 1.6.0
- Added in-place full-screen redraw handling, pinning, a compact toolbar, and CPU/GPU/RAM status.

## 1.5.1
- Corrected watcher line-feed and scroll-follow rendering.

## 1.5.0
- Added terminal-screen handling for carriage returns, cursor movement, erase, and clear sequences.

## 1.4.0
- Added 60 Hz batched rendering.

## 1.3.1
- Improved terminal-control cleanup and Runner startup location.

## 1.3.0
- Improved terminal formatting and scrolling behavior.

## 1.2.0
- Added persistent Runner sessions and command history.

## 1.1.0
- Added incremental native text rendering for smoother output.
