# RedTrace for macOS

> A local-first command activity viewer, interactive terminal workspace, and live system monitor for macOS.

RedTrace brings your shell sessions, ChatGPT/Codex command activity, and system telemetry into one native macOS app. Its terminal and hook logs stay on your Mac under `~/.redtrace`.

## Highlights

- **Native interactive terminal** — persistent zsh sessions backed by a real pseudo-terminal (PTY), so terminal-aware tools receive a TTY
- **Live Watch** — follow all supported shells or select an individual source
- **ChatGPT activity** — readable local hook events for commands, inputs, results, exit status, and errors
- **System dashboard** — CPU, best-effort GPU, memory, disk, network, and process telemetry
- **Flexible workspace** — use focused tabs or a responsive card dashboard; open dedicated Watch, Run, ChatGPT, and BTOP windows
- **Made for macOS** — red-and-black theme, native menu-bar access, background mode, opacity, custom fonts/colors, and an always-on-top option
- **Command help** — Common Commands menus insert a command for review; choosing one never runs it

## Install

### Download a release

Download the latest macOS package from [Releases](../../releases), unpack it, then run:

```bash
./install.sh
```

### Build from source

Requirements:

- macOS 13 Ventura or later (Intel and Apple silicon; macOS 15 supported)
- Apple Command Line Tools: `xcode-select --install`
- zsh (included with macOS)

```bash
./build.sh
./install.sh
```

## Using RedTrace

1. Open **RUN** and enter a command to start a persistent zsh terminal.
2. Use **WATCH** to follow all supported terminal activity or select a live shell source.
3. Switch between **Tabs** for a focused workspace and **Cards** for a live dashboard.
4. Open **ChatGPT** to review activity delivered by the installed hooks.
5. Click the RedTrace menu-bar icon to open the quick panel while the app runs in the background.

## ChatGPT/Codex activity

Open `/hooks` in a local Codex session, approve the RedTrace hook entries, then begin a new local session. RedTrace records supported tool activity locally and shows command lifecycle events, target/input details, output, exit status, and errors when supplied.

RedTrace cannot passively attach to an unrelated cloud conversation. It can show the events delivered to its local hooks.

## Privacy and limitations

- RedTrace captures terminal activity through its supported shell integration and sessions it launches. It does not attempt to capture secure prompts or passwords.
- Full-screen terminal programs and applications that bypass ordinary terminal streams may not render perfectly.
- GPU utilization is best-effort on Intel Macs and displays a dash when macOS does not expose it.
- Review commands before running them. Runner commands use your macOS account permissions.
- Logs remain local and are restricted to your user account. The combined terminal log rotates at roughly 10 MB.

## Uninstall

Run:

```bash
./uninstall.sh
```

This removes the app, its `~/.zshrc` integration, and only RedTrace hook entries. It deliberately leaves `~/.redtrace` logs in place; delete that folder separately if you no longer want them.

## Release notes

See [CHANGELOG.md](CHANGELOG.md) for the complete release history.
