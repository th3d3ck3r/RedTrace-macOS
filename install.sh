#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP_NAME="RedTrace"
APP_DIR="$HOME/Applications/$APP_NAME.app"
SUPPORT_DIR="$HOME/.redtrace"
LEGACY_APP_DIR="$HOME/Applications/CommandGlass.app"
LEGACY_SUPPORT_DIR="$HOME/.commandglass"
ZSHRC="$HOME/.zshrc"
START_MARKER="# >>> RedTrace >>>"
END_MARKER="# <<< RedTrace <<<"

mkdir -p "$HOME/Applications" "$SUPPORT_DIR"
chmod 700 "$SUPPORT_DIR"
if [[ -f "$LEGACY_SUPPORT_DIR/stream.log" && ! -f "$SUPPORT_DIR/stream.log" ]]; then
  cp "$LEGACY_SUPPORT_DIR/stream.log" "$SUPPORT_DIR/stream.log"
fi
if [[ -f "$LEGACY_SUPPORT_DIR/codex-events.jsonl" && ! -f "$SUPPORT_DIR/codex-events.jsonl" ]]; then
  cp "$LEGACY_SUPPORT_DIR/codex-events.jsonl" "$SUPPORT_DIR/codex-events.jsonl"
fi
cp "$ROOT/shell-integration.zsh" "$SUPPORT_DIR/shell-integration.zsh"
cp "$ROOT/codex-hook.py" "$SUPPORT_DIR/codex-hook.py"
cp "$ROOT/install-codex-hooks.py" "$SUPPORT_DIR/install-codex-hooks.py"
chmod 700 "$SUPPORT_DIR/codex-hook.py" "$SUPPORT_DIR/install-codex-hooks.py"
touch "$SUPPORT_DIR/stream.log" "$SUPPORT_DIR/codex-events.jsonl" "$ZSHRC"
chmod 600 "$SUPPORT_DIR/stream.log" "$SUPPORT_DIR/codex-events.jsonl"
python3 "$SUPPORT_DIR/install-codex-hooks.py" install

if [[ -d "$APP_DIR" ]]; then
  rm -rf "$APP_DIR"
fi
if [[ -d "$LEGACY_APP_DIR" ]]; then
  rm -rf "$LEGACY_APP_DIR"
fi
"$ROOT/build.sh" "$APP_DIR"

sed -i '' '/# >>> CommandGlass >>>/,/# <<< CommandGlass <<</d' "$ZSHRC"
sed -i '' '/# >>> RedTrace >>>/,/# <<< RedTrace <<</d' "$ZSHRC"
{
  print ""
  print "$START_MARKER"
  print '[[ -r "$HOME/.redtrace/shell-integration.zsh" ]] && source "$HOME/.redtrace/shell-integration.zsh"'
  print "$END_MARKER"
} >> "$ZSHRC"

xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true
open "$APP_DIR"

print ""
print "RedTrace is installed in $APP_DIR"
print "Open a new Terminal or iTerm tab to begin mirroring output."
print "In the Codex CLI, open /hooks and review/trust the RedTrace hooks, then start a new Codex session."
