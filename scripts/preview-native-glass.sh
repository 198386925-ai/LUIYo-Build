#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p native-glass-preview
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); choices=[x for k,v in d["devices"].items() if "iOS-26-" in k for x in v if x.get("isAvailable") and x["name"].startswith("iPhone")]; print(next((x["udid"] for x in choices if x["name"] == "iPhone 17 Pro"), choices[0]["udid"]))')
xcodebuild -project YouYouLUI_iOS/YouYouLUI.xcodeproj -scheme YouYouLUI \
  -configuration Debug -sdk iphonesimulator -destination "id=$DEVICE" \
  -derivedDataPath native-preview-build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-" ONLY_ACTIVE_ARCH=YES \
  build > native-glass-preview/build.log 2>&1 || { tail -100 native-glass-preview/build.log; exit 1; }
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --batteryState charged --batteryLevel 100
APP=native-preview-build/Build/Products/Debug-iphonesimulator/YouYouLUI.app
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
xcrun simctl install "$DEVICE" "$APP"
for SCENARIO in light dark colors-light wechat-light tail-light; do
  APPEARANCE=${SCENARIO##*-}
  xcrun simctl ui "$DEVICE" appearance "$APPEARANCE"
  DATA_DIR=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)
  rm -f "$DATA_DIR/Documents/native-glass-ready.txt"
  SIMCTL_CHILD_LUI_SNAPSHOT="preview-native-glass-home-$SCENARIO" xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID"
  for ATTEMPT in $(seq 1 45); do
    if [ -f "$DATA_DIR/Documents/native-glass-ready.txt" ]; then break; fi
    sleep 1
  done
  test -f "$DATA_DIR/Documents/native-glass-ready.txt"
  cp "$DATA_DIR/Documents/native-glass-evidence.json" "native-glass-preview/evidence-$SCENARIO.json"
  xcrun simctl io "$DEVICE" screenshot "native-glass-preview/LUIYo-native-glass-home-$SCENARIO.png"
  python3 - "native-glass-preview/evidence-$SCENARIO.json" <<'PY'
import json,sys
e=json.load(open(sys.argv[1])); assert e['osVersion'].startswith('26.'),e
assert any('glass' in c.lower() for c in e['runtimeGlassClasses']),e
assert e['catalogEntries'] == sum(e['catalogCounts'].values()),e
assert all(n > 6 for n in e['catalogCounts'].values()),e
if 'wechat' in sys.argv[1]: assert e['activeCategory'] == 'wechat',e
print(e)
PY
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID"
done
python3 - <<'PY'
from pathlib import Path
folder = Path('native-glass-preview')
assert (folder / 'LUIYo-native-glass-home-light.png').read_bytes() != (folder / 'LUIYo-native-glass-home-wechat-light.png').read_bytes(), 'WeChat category screenshot must differ from LiquidUI'
PY
