#!/bin/bash
set -euo pipefail
mkdir -p native-check
UDID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin);print(next(x["udid"] for k,v in d["devices"].items() if "iOS-26" in k for x in v if x["name"].startswith("iPhone")))')
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcodebuild -project YouYouLUI_iOS/YouYouLUI.xcodeproj -scheme YouYouLUI -configuration Debug -sdk iphonesimulator -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath native-check/build -resultBundlePath native-check/license-export.xcresult -only-testing:LUIYoUITests/NativeNavigationTests/testInlineActivationAndFullExport CODE_SIGNING_ALLOWED=NO test 2>&1 | tee native-check/license-export.log
