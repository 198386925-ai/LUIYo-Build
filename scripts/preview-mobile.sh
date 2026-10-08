#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p mobile-preview
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for key,values in d["devices"].items() if "iOS-26-" in key for x in values if x.get("isAvailable") and x["name"].startswith("iPhone")))')
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --batteryState charged --batteryLevel 100
xcodebuild test -project YouYouLUI_iOS/YouYouLUI.xcodeproj -scheme YouYouLUI \
  -configuration Release -sdk iphonesimulator -destination "id=$DEVICE" \
  -derivedDataPath sim-preview -resultBundlePath mobile-preview/ui-tests.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-" ONLY_ACTIVE_ARCH=YES
APP=sim-preview/Build/Products/Release-iphonesimulator/YouYouLUI.app
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl ui "$DEVICE" appearance light
for SCENE in preview-home preview-rules preview-settings preview-search-home preview-search-rules preview-search-settings; do
  DATA_DIR=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)
  rm -f "$DATA_DIR/Documents/preview-ready.txt"
  SIMCTL_CHILD_LUI_SNAPSHOT="$SCENE" xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID"
  for ATTEMPT in $(seq 1 90); do
    if [ -f "$DATA_DIR/Documents/preview-ready.txt" ]; then break; fi
    sleep 1
  done
  test -f "$DATA_DIR/Documents/preview-ready.txt"
  xcrun simctl io "$DEVICE" screenshot "mobile-preview/$SCENE.png"
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID"
done
