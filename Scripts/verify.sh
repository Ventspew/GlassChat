#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macosx15.0"

echo "==> Parsing Swift sources"
swiftc -sdk "$SDK" -target "$TARGET" -parse \
  GlassChat/App/*.swift \
  GlassChat/Features/Sidebar/*.swift \
  GlassChat/Features/Chat/*.swift \
  GlassChat/Features/Composer/*.swift \
  GlassChat/Features/Settings/*.swift \
  GlassChat/Features/Linking/*.swift \
  GlassChat/Models/*.swift \
  GlassChat/Messaging/*.swift \
  GlassChat/Themes/*.swift \
  GlassChat/Translation/*.swift \
  GlassChat/Security/*.swift

echo "==> Go bridge tests"
(
  cd Bridge
  go test ./...
)

if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
  echo "==> xcodebuild"
  xcodegen generate
  xcodebuild -scheme GlassChat -destination 'platform=macOS' build
else
  echo "==> Skipping xcodebuild (full Xcode.app not available)"
fi

echo "OK"
