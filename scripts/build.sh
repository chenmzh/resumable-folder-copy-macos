#!/bin/zsh

set -euo pipefail
unsetopt BG_NICE

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$PROJECT_ROOT/build"
APP_ROOT="$BUILD_ROOT/Resumable Folder Copy.app"
CONTENTS="$APP_ROOT/Contents"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$BUILD_ROOT/module-cache-arm64" "$BUILD_ROOT/module-cache-x86_64"

clang -fobjc-arc -fmodules -fmodules-cache-path="$BUILD_ROOT/module-cache-arm64" \
  -framework Cocoa -arch arm64 "$PROJECT_ROOT/src/main.m" \
  -o "$BUILD_ROOT/ResumableFolderCopy-arm64"

clang -fobjc-arc -fmodules -fmodules-cache-path="$BUILD_ROOT/module-cache-x86_64" \
  -framework Cocoa -arch x86_64 "$PROJECT_ROOT/src/main.m" \
  -o "$BUILD_ROOT/ResumableFolderCopy-x86_64"

lipo -create "$BUILD_ROOT/ResumableFolderCopy-arm64" "$BUILD_ROOT/ResumableFolderCopy-x86_64" \
  -output "$CONTENTS/MacOS/ResumableFolderCopy"

cp "$PROJECT_ROOT/resources/Info.plist" "$CONTENTS/Info.plist"
cp "$PROJECT_ROOT/src/transfer.zsh" "$CONTENTS/Resources/transfer.zsh"
for locale_dir in "$PROJECT_ROOT"/locales/*.lproj; do cp -R "$locale_dir" "$CONTENTS/Resources/"; done
chmod +x "$CONTENTS/MacOS/ResumableFolderCopy" "$CONTENTS/Resources/transfer.zsh"
codesign --force --deep --sign - "$APP_ROOT"
codesign --verify --deep --strict "$APP_ROOT"

ditto -c -k --sequesterRsrc --keepParent "$APP_ROOT" "$BUILD_ROOT/Resumable-Folder-Copy-v2.2.0-macOS-universal.zip"
print -- "Built: $APP_ROOT"
