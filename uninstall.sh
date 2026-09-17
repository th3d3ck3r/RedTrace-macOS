#!/bin/zsh
set -euo pipefail

APP_DIR="$HOME/Applications/RedTrace.app"
ZSHRC="$HOME/.zshrc"

osascript -e 'tell application "RedTrace" to quit' 2>/dev/null || true

if [[ -f "$HOME/.redtrace/install-codex-hooks.py" ]]; then
  python3 "$HOME/.redtrace/install-codex-hooks.py" uninstall || true
fi

if [[ -f "$ZSHRC" ]]; then
  sed -i '' '/# >>> RedTrace >>>/,/# <<< RedTrace <<</d' "$ZSHRC"
  sed -i '' '/# >>> CommandGlass >>>/,/# <<< CommandGlass <<</d' "$ZSHRC"
fi

rm -rf "$APP_DIR"
print "RedTrace was removed."
print "Your private logs remain in $HOME/.redtrace; delete that folder if you no longer want them."
