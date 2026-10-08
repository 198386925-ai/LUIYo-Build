#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcodebuild -version
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
case "$SDK_VERSION" in
  26.*) ;;
  *) echo "ERROR: This workflow requires an iOS 26 SDK; found $SDK_VERSION"; exit 1 ;;
esac
node YouYouLUI_iOS/verify-material-bridge.js YouYouLUI_iOS/YouYouLUI/Web/index.html
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
test "$VERSION" = '1.0.4'
test "$BUILD" = '15'
STAGE=$(mktemp -d "$ROOT/build/package.XXXXXX")
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
NAME="LUIYo-v${VERSION}-build${BUILD}-ios26-${GITHUB_RUN_NUMBER:-local}-unsigned.ipa"
(cd "$STAGE" && /usr/bin/zip -qry "$ROOT/output/$NAME" Payload)
unzip -t "output/$NAME"
echo "IPA: output/$NAME (unsigned; sign before installation)"
