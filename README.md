# RedTrace for macOS

RedTrace is a small always-on-top window that mirrors your interactive zsh sessions. It shows commands, standard output, and errors from every **new** Terminal, iTerm2, Warp, or VS Code terminal session after installation.

## 2.7 — Interactive terminal and ChatGPT activity

RedTrace 2.7 upgrades Runner to a RedTrace-owned PTY. Each Runner starts interactive zsh with `TERM=xterm-256color`, accepts direct keyboard input and paste, supports terminal resizing, and no longer disables terminal colors. The terminal model handles common cursor, erase, style, alternate-screen, cursor-visibility, bracketed-paste, and terminal-query sequences while batching redraws for smooth output.

The former CODEX interface is now **CHATGPT**. Minimal, Normal, and Verbose displays share one local activity stream. It represents observable tool activity only—commands, reads, searches, edits, writes, targets, timing, results, and local/remote metadata—and never exposes or claims hidden reasoning.

### 2.7.0 changelog

- Added native `forkpty` Runner transport and clean shell reaping.
- Added interactive terminal input, paste, resize, styles, alternate-screen handling, and terminal protocol responses.
- Added normalized, bounded ChatGPT activity history with Minimal, Normal, and Verbose views.
- Renamed user-facing CODEX labels to CHATGPT.
- Updated hooks to record non-command tool events plus target, input, exit-code, and error metadata.
- Added macOS GitHub Actions compilation and hook-syntax validation.

## Install

1. Unzip the download.
2. Open Terminal and drag `install.sh` into the window, then press Return.
3. If macOS asks, allow Terminal to run the script.
4. Open a new terminal tab. Its activity will appear in RedTrace.
5. In the Codex CLI, open `/hooks`, review and trust the two RedTrace hooks, then start a new Codex session. Normal ChatGPT chats do not expose `/hooks`.

You can also run:

```zsh
cd /path/to/RedTrace
./install.sh
```

The app is installed at `~/Applications/RedTrace.app`. Drag the window anywhere and resize it. Open the palette button to adjust transparency, font, font size, text color, and background color. Use the multiple-window button to choose a dedicated Watcher, Runner, Codex, or BTOP window. Every Runner gets an isolated zsh session and its own output. The toolbar also lets you toggle line wrapping. Use the pin button to toggle always-on-top; windows continue to follow you across Spaces.

Version 2.0 introduces the RedTrace name and red trace-monitor icon. Installing it removes the old CommandGlass application and shell block, migrates the existing combined terminal and Codex event logs, and replaces the old Codex hook entries without touching unrelated hooks.

Version 2.0.1 replaces the SwiftUI color pickers with native macOS color wells so text and background changes apply immediately and persist reliably.

Version 2.0.2 uses the supplied RedTrace artwork as a polished native macOS icon, with a transparent exterior, standard rounded-square silhouette, balanced padding, and complete multi-resolution `.icns` data.

Version 2.0.3 replaces shell-wide output redirection with pseudo-terminal capture. Programs now see real terminal streams, fixing `stdout is not a terminal` failures in interactive installers, `sudo`, progress interfaces, and other TTY-aware commands while retaining ordered Watcher output.

Version 2.6 adds a categorized Common Commands menu to every Runner in Tabs, Cards, and dedicated windows. Navigation, Git, system, and development commands are inserted into the command field for review and editing; they never execute merely by selecting them. The Windows port uses the same interaction with shell-specific PowerShell, CMD, and WSL command lists.

Version 2.6.1 gives the BTOP system-monitor cards the same `AUTO`, 1, 2, 3, and 4 column choices as the main Cards dashboard. The control is available in the full BTOP tab/window and directly from the BTOP pane header on the main Cards page. `AUTO` responds to the available monitor width, while manual column choices and card heights remain independent. Reset restores automatic columns, the default order, and default heights.

Version 2.6.2 makes the `CARDS` pill a menu for showing or hiding WATCH, RUN, CODEX, and BTOP independently. Hidden cards are removed from the responsive grid so the remaining cards refill the available space. Cards mode now keeps only the Watch card's terminal-source selector, removing the duplicate selector from the main toolbar.

Version 2.5.2 separates responsive height fitting from column selection. `Fit cards to window` now stays enabled when choosing `AUTO`, 1, 2, 3, or 4 columns; only dragging a card’s resize handle switches height fitting off. `AUTO` changes columns with window width, and Reset restores both automatic columns and fitted heights.

Version 2.5.1 makes Cards responsive. Auto-fit chooses an appropriate column count from the window width and divides the available height across its rows so all four panes fit whenever the minimum usable card height allows it. Manually resizing a card switches to manual height layout; Reset returns to auto-fit.

Version 2.5 adds two main-window layouts. Tabs keeps the familiar single-page mode; Cards shows live WATCH, RUN, CODEX, and BTOP panes together with draggable headers, individual resize handles, one-to-four-column layouts, and dedicated-window buttons. The toolbar layout button switches modes. The decorative status dot and visible window-drag grip are removed; drag the empty toolbar area to move a window. Codex hook installation now matches supported tool events broadly, captures both `cmd` and `command` payloads, and runs an isolated end-to-end self-test before reporting success.

Version 2.4 adds a native RedTrace menu-bar icon and a full tabbed quick panel. RedTrace continues running when its ordinary windows are closed; click the waveform icon in the macOS menu bar to open the panel. The Watcher now verifies session PIDs, displays only live terminals, and removes stale per-session logs while retaining their output in the combined `All terminals` log.

Version 2.3.1 prevents window dragging from stealing BTOP card gestures. Windows now move only from the compact grip at the left side of the toolbar, while cards can be dragged and resized independently.

Version 2.3 makes the BTOP metric cards movable by dragging and individually height-resizable from their lower-right handles. Its layout menu changes the dashboard between one and four columns or resets the arrangement. The show-toolbar control now sits above every tab, fixing the hidden toolbar trap in BTOP.

Version 2.2.1 introduces the RedTrace default theme: vivid red terminal text and controls, restrained red window accents, a black background, and 85% window opacity. The appearance panel now labels opacity accurately and shows its percentage.

Version 2.2 keeps the primary RedTrace window tabbed while making every window opened from the new-window menu a dedicated `WATCH`, `RUN`, `CODEX`, or `BTOP` window. Dedicated windows have independent sessions, output buffers, source choices, and pin state, and cannot accidentally switch roles.

Version 2.1 adds a native `BTOP` tab with 60-sample CPU and memory history, root-disk usage, live upload/download rates, and the highest-CPU processes. It uses built-in macOS statistics and commands, so the third-party `btop` package is not required.

Version 1.1 uses incremental native text rendering for smoother updates, even while commands are producing output rapidly. Version 1.2 refreshes near 30 frames per second and only auto-follows new output when you are already near the bottom, so scrolling back through output remains smooth.

Version 1.3.1 cleans terminal color, title, cursor, and path-control sequences before displaying output. Runner shells start in your home folder rather than the filesystem root.

Version 1.4 targets a 60 Hz display cadence. Watchers check for output every 16.67 milliseconds, while Runners batch shell-output fragments and commit them once per frame to avoid uneven redraw bursts.

Version 1.5 adds a virtual terminal screen buffer. Progress displays that use carriage returns, cursor movement, erase-line, or clear-screen instructions now repaint existing lines instead of creating repeated copies. The native text view replaces only the changed suffix to keep these in-place updates smooth at 60 Hz.

Version 1.5.1 treats watcher line feeds like terminal newlines, removes invisible trailing padding, and preserves the left edge during auto-follow. This prevents shifted or clipped text when progress displays align themselves to a source terminal's width.

Version 1.6 recognizes full-frame `erase-to-end` plus `cursor-home` redraws, based on captured terminal output. Each window now has persistent Watcher and Runner tabs, a per-window always-on-top pin, a slimmer 30-point toolbar, and compact CPU/GPU/RAM readings. GPU utilization is best-effort on Intel Macs and displays a dash when macOS does not expose it. The shell hook also merges stdout and stderr into one ordered capture stream.

Version 1.7 added a `CODEX` tab and Codex command bridge. Commands and results appear with clear `[LOCAL]` or `[REMOTE]` labels. Watchers have a source selector: choose `All terminals` or one individual shell, independently in every window.

## Run commands inside RedTrace

Version 1.2 adds a command bar to Runner windows. Type a command and press Return. Each Runner has its own persistent interactive zsh session, so its working directory, aliases, and exported variables remain available for later commands in that window. Use the arrow buttons to revisit command history. The stop button ends a stuck command and starts a fresh shell session.

Commands entered here run with your macOS user permissions, just like commands entered in Terminal. Review destructive commands carefully before running them.

## What it captures

- Commands entered in new interactive zsh sessions
- stdout and stderr from those sessions
- Activity across Terminal, iTerm2, Warp, and VS Code terminals that load `~/.zshrc`
- Codex Bash-command start and completion events from sessions where the RedTrace hooks are active

It does not spy on unrelated processes or capture passwords typed into secure prompts. Full-screen terminal programs and apps that bypass shell output redirection may not render perfectly.

The `REMOTE` label applies when Codex supplies remote/cloud execution metadata or the command runs from a known remote workspace path. RedTrace cannot passively attach to an arbitrary ChatGPT conversation that is already running in the cloud. A remote session must use a Codex client or app-server connection that delivers its command events to the hooks on this Mac.

Terminal and Codex event logs stay on your Mac under `~/.redtrace`. Files are restricted to your user account. The combined terminal log rotates down when it grows beyond about 10 MB.

## Uninstall

Run `uninstall.sh`. This removes the app, its `~/.zshrc` integration, and only the RedTrace entries from your Codex hooks. It deliberately leaves private logs in place; delete `~/.redtrace` yourself if you no longer want them.

## Requirements

- macOS 13 Ventura or newer (Intel and Apple silicon; macOS 15 supported)
- Apple's free Command Line Tools (`xcode-select --install` if needed)
- zsh (the macOS default shell)
