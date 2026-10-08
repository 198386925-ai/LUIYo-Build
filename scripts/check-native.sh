#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for key,values in d["devices"].items() if "iOS-26-" in key for x in values if x.get("isAvailable") and x["name"].startswith("iPhone")))')
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcodebuild -project YouYouLUI_iOS/YouYouLUI.xcodeproj -scheme YouYouLUI \
  -configuration Release -sdk iphonesimulator -destination "id=$DEVICE" \
  -derivedDataPath sim-build CODE_SIGNING_ALLOWED=NO build
APP=sim-build/Build/Products/Release-iphonesimulator/YouYouLUI.app
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
mkdir -p native-check
for SCENE in home-liquid settings-liquid bottom-home-liquid bottom-separate-home-liquid dark-bottom-separate-home-liquid bottom-off-home-liquid; do
  xcrun simctl install "$DEVICE" "$APP"
  DATA_DIR=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)
  rm -f "$DATA_DIR/Documents/ui-layout-verification.json"
  SIMCTL_CHILD_LUI_SNAPSHOT="$SCENE" xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID"
  for ATTEMPT in $(seq 1 60); do
    if [ -f "$DATA_DIR/Documents/ui-layout-verification.json" ]; then break; fi
    sleep 1
  done
  test -f "$DATA_DIR/Documents/ui-layout-verification.json"
  cp "$DATA_DIR/Documents/ui-layout-verification.json" "native-check/$SCENE.json"
  xcrun simctl io "$DEVICE" screenshot "native-check/$SCENE.png"
  python3 - "$SCENE" "native-check/$SCENE.json" <<'PY'
import json, sys
scene, path = sys.argv[1:]
result = json.load(open(path))
assert result['passed'], result
assert result['appVersion'] == '1.0.4' and result['appBuild'] == '15', result
assert result.get('nativeSeparateSearch', False) == ('separate' in scene), result
if scene == 'home-liquid':
    assert result['searchLiquid'] and not result['searchBlur'], result
if scene == 'bottom-home-liquid':
    assert result['nativeSearchEnabled'] and result['bottomSearchEnabled'], result
print('Native check passed:', scene)
PY
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID"
done
