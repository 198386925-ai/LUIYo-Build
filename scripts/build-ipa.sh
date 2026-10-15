#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Restore files split for transfer (ensures 100% consistency with the release package).
# index.html is stored in parts; images are stored base64-encoded (binary-safe).
SPLIT_DIR="scripts/split-assets"
if [ -d "$SPLIT_DIR" ]; then
  if ls "$SPLIT_DIR"/index.html.part* >/dev/null 2>&1; then
    cat "$SPLIT_DIR"/index.html.part* > "YouYouLUI_iOS/YouYouLUI/Web/index.html"
  fi
  restore_img() { if [ -f "$SPLIT_DIR/$1" ]; then python3 -c "import base64,sys; sys.stdout.buffer.write(base64.b64decode(open(sys.argv[1]).read()))" "$SPLIT_DIR/$1" > "$2"; fi; }
  restore_img "Reference.jpeg.b64" "YouYouLUI_iOS/YouYouLUI/Assets.xcassets/BrandReference.imageset/Reference.jpeg"
  restore_img "ToolbarClear-Icon.png.b64" "YouYouLUI_iOS/YouYouLUI/Assets.xcassets/ToolbarClear.imageset/Icon.png"
  restore_img "ToolbarExport-Icon.png.b64" "YouYouLUI_iOS/YouYouLUI/Assets.xcassets/ToolbarExport.imageset/Icon.png"
  restore_img "ToolbarFill-Icon.png.b64" "YouYouLUI_iOS/YouYouLUI/Assets.xcassets/ToolbarFill.imageset/Icon.png"
  restore_img "ToolbarImport-Icon.png.b64" "YouYouLUI_iOS/YouYouLUI/Assets.xcassets/ToolbarImport.imageset/Icon.png"
  restore_img "ToolbarSupport-Icon.png.b64" "YouYouLUI_iOS/YouYouLUI/Assets.xcassets/ToolbarSupport.imageset/Icon.png"
fi
python3 scripts/render-release-notes.py
node scripts/sync-native-preview-catalog.js --check
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
true
true
STAGE=$(mktemp -d "$ROOT/build/package.XXXXXX")
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
NAME="LUIYo-v${VERSION}-build${BUILD}-ios26-${GITHUB_RUN_NUMBER:-local}-unsigned.ipa"
(cd "$STAGE" && /usr/bin/zip -qry "$ROOT/output/$NAME" Payload)
unzip -t "output/$NAME"
echo "IPA: output/$NAME (unsigned; sign before installation)"


