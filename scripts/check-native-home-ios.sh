#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p native-home-check
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); devices=[x for k,v in d["devices"].items() if "iOS-26-" in k for x in v if x.get("isAvailable") and x["name"].startswith("iPhone")]; print(next((x["udid"] for x in devices if x["name"] == "iPhone 17 Pro"),devices[0]["udid"]))')
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --batteryState charged --batteryLevel 100
xcodebuild -project YouYouLUI_iOS/YouYouLUI.xcodeproj -scheme YouYouLUI -configuration Debug -sdk iphonesimulator \
  -destination "id=$DEVICE" -derivedDataPath native-home-test-build \
  -resultBundlePath native-home-check/NativeHome.xcresult \
  -only-testing:LUIYoUITests/NativeNavigationTests/testNativeHomeActivationAndExport \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-" ONLY_ACTIVE_ARCH=YES test \
  > native-home-check/test.log 2>&1 || { tail -100 native-home-check/test.log; exit 1; }
xcrun xcresulttool export attachments --path native-home-check/NativeHome.xcresult --output-path native-home-check/screenshots
