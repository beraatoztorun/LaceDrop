#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
APP_DIR="$PROJECT_DIR/build/LaceDrop.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE="$PROJECT_DIR/build/module-cache"
SAVER_DIR="$PROJECT_DIR/build/LaceDrop.saver"
SAVER_CONTENTS="$SAVER_DIR/Contents"
SAVER_MACOS="$SAVER_CONTENTS/MacOS"
SAVER_RESOURCES="$SAVER_CONTENTS/Resources"

/bin/rm -rf "$APP_DIR" "$SAVER_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE" \
  "$SAVER_MACOS" "$SAVER_RESOURCES"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" /usr/bin/clang \
  -fobjc-arc \
  -fmodules \
  -Wall \
  -Wextra \
  -Wno-deprecated-declarations \
  -mmacosx-version-min=13.0 \
  -framework AppKit \
  -framework QuartzCore \
  -framework Metal \
  -framework MetalKit \
  "$PROJECT_DIR/Sources/main.m" \
  "$PROJECT_DIR/Sources/LaceView.m" \
  "$PROJECT_DIR/Sources/LaceMetalView.m" \
  -o "$MACOS_DIR/LaceDrop"

cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/LaceTexture-Flower.png" "$RESOURCES_DIR/LaceTexture-Flower.png"
cp "$PROJECT_DIR/Resources/LaceTexture-Tulip.png" "$RESOURCES_DIR/LaceTexture-Tulip.png"
cp "$PROJECT_DIR/Resources/LaceTexture-Vine.png" "$RESOURCES_DIR/LaceTexture-Vine.png"
cp "$PROJECT_DIR/Resources/LaceTexture-Geometric.png" "$RESOURCES_DIR/LaceTexture-Geometric.png"
/usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" /usr/bin/clang \
  -fobjc-arc \
  -fmodules \
  -bundle \
  -Wall \
  -Wextra \
  -Wno-deprecated-declarations \
  -mmacosx-version-min=13.0 \
  -I"$PROJECT_DIR/Sources" \
  -framework AppKit \
  -framework QuartzCore \
  -framework Metal \
  -framework MetalKit \
  -framework ScreenSaver \
  "$PROJECT_DIR/ScreenSaver/LaceDropScreenSaverView.m" \
  "$PROJECT_DIR/Sources/LaceView.m" \
  "$PROJECT_DIR/Sources/LaceMetalView.m" \
  -o "$SAVER_MACOS/LaceDropScreenSaver"

cp "$PROJECT_DIR/ScreenSaverResources/Info.plist" "$SAVER_CONTENTS/Info.plist"
cp "$PROJECT_DIR/Resources/LaceTexture-Flower.png" "$SAVER_RESOURCES/LaceTexture-Flower.png"
cp "$PROJECT_DIR/Resources/LaceTexture-Tulip.png" "$SAVER_RESOURCES/LaceTexture-Tulip.png"
cp "$PROJECT_DIR/Resources/LaceTexture-Vine.png" "$SAVER_RESOURCES/LaceTexture-Vine.png"
cp "$PROJECT_DIR/Resources/LaceTexture-Geometric.png" "$SAVER_RESOURCES/LaceTexture-Geometric.png"
/usr/bin/codesign --force --deep --sign - "$SAVER_DIR" >/dev/null

echo "$APP_DIR"
echo "$SAVER_DIR"
