#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Restore known-good sources and apply background-overlap fix if needed.
# Allows CI to build a fixed IPA even when main temporarily has broken placeholders.
GOOD_SHA="${LUIYO_GOOD_SHA:-8aaba2a3162f4475b912a40af9a417b5e98b2eef}"
NEED_FIX=0
if ! grep -q 'clearAllNativeCardMaterials' YouYouLUI_iOS/YouYouLUI/WebViewController.swift 2>/dev/null; then
  NEED_FIX=1
fi
if ! grep -q 'requestAnimationFrame(()=>{try{window.__syncNativeCardGlass' YouYouLUI_iOS/YouYouLUI/Web/index.html 2>/dev/null; then
  NEED_FIX=1
fi
if [ "$NEED_FIX" = 1 ]; then
  echo "Applying background-overlap fix onto ${GOOD_SHA} sources..."
  curl -fsSL "https://raw.githubusercontent.com/198386925-ai/LUIYo-Build/${GOOD_SHA}/YouYouLUI_iOS/YouYouLUI/WebViewController.swift" \
    -o YouYouLUI_iOS/YouYouLUI/WebViewController.swift
  curl -fsSL "https://raw.githubusercontent.com/198386925-ai/LUIYo-Build/${GOOD_SHA}/YouYouLUI_iOS/YouYouLUI/Web/index.html" \
    -o YouYouLUI_iOS/YouYouLUI/Web/index.html
  patch -p1 < patches/WebViewController.swift.patch
  patch -p1 < patches/index.html.patch
  grep -q 'clearAllNativeCardMaterials' YouYouLUI_iOS/YouYouLUI/WebViewController.swift
  grep -q '__syncNativeCardGlass' YouYouLUI_iOS/YouYouLUI/Web/index.html
  echo "Background-overlap fix applied."
fi

python3 scripts/render-release-notes.py
xcodebuild -version
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
case "$SDK_VERSION" in
  26.*) ;;
  *) echo "ERROR: This workflow requires an iOS 26 SDK; found $SDK_VERSION"; exit 1 ;;
esac
node YouYouLUI_iOS/verify-material-bridge.js YouYouLUI_iOS/YouYouLUI/Web/index.html
# Produce the marketing rendition from the existing app icon when absent.
# The installed iPhone/iPad icon renditions keep their original bytes.
ICON_SET=YouYouLUI_iOS/YouYouLUI/Assets.xcassets/AppIcon.appiconset
if [ ! -f "$ICON_SET/Icon-1024.png" ]; then
  sips --resampleHeightWidth 1024 1024 "$ICON_SET/Icon-60@3x.png" --out "$ICON_SET/Icon-1024.png"
fi
python3 - "$ICON_SET" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for image in json.loads((root / 'Contents.json').read_text())['images']:
    assert (root / image['filename']).is_file(), image['filename']
PY
mkdir -p output
xcodebuild \
  -project YouYouLUI_iOS/YouYouLUI.xcodeproj \
  -scheme YouYouLUI -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
APP=build/Build/Products/Release-iphoneos/YouYouLUI.app
test -f "$APP/YouYouLUI"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")
BUILT_SDK=$(/usr/libexec/PlistBuddy -c 'Print :DTSDKName' "$APP/Info.plist")
case "$BUILT_SDK" in iphoneos26.*) ;; *) echo "ERROR: Incorrect built SDK: $BUILT_SDK"; exit 1 ;; esac
test "$VERSION" = '1.0.5'
test "$BUILD" = '26'
STAGE=$(mktemp -d "$ROOT/build/package.XXXXXX")
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
NAME="LUIYo-v${VERSION}-build${BUILD}-ios26-${GITHUB_RUN_NUMBER:-local}-unsigned.ipa"
(cd "$STAGE" && /usr/bin/zip -qry "$ROOT/output/$NAME" Payload)
unzip -t "output/$NAME"
echo "IPA: output/$NAME (unsigned; sign before installation)"
