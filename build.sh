#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
OUTPUT="${1:-$ROOT/build/RedTrace.app}"
MACOS_DIR="$OUTPUT/Contents/MacOS"
ARCH="$(uname -m)"

if ! command -v xcrun >/dev/null 2>&1; then
  print -u2 "Apple Command Line Tools are required. Run: xcode-select --install"
  exit 1
fi

if [[ "$ARCH" != "x86_64" && "$ARCH" != "arm64" ]]; then
  print -u2 "Unsupported Mac architecture: $ARCH"
  exit 1
fi

mkdir -p "$MACOS_DIR"

xcrun swiftc \
  -parse-as-library \
  -O \
  -target "$ARCH-apple-macosx13.0" \
  -framework SwiftUI \
  -framework AppKit \
  "$ROOT/TerminalCore.swift" \
  "$ROOT/PTYSession.swift" \
  "$ROOT/TerminalView.swift" \
  "$ROOT/Activity.swift" \
  "$ROOT/ComputerBackend.swift" \
  "$ROOT/CodexChat.swift" \
  "$ROOT/RedTrace.swift" \
  -o "$MACOS_DIR/RedTrace"

cp "$ROOT/Info.plist" "$OUTPUT/Contents/Info.plist"
mkdir -p "$OUTPUT/Contents/Resources"
cp "$ROOT/RedTrace.icns" "$OUTPUT/Contents/Resources/RedTrace.icns"
chmod +x "$MACOS_DIR/RedTrace"
codesign --force --deep --sign - "$OUTPUT"

print "Built $OUTPUT"
