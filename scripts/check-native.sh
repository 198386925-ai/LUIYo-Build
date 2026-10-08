#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for key,values in d["devices"].items() if "iOS-26-" in key for x in values if x.get("isAvailable") and x["name"].startswith("iPhone")))')
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcodebuild -project YouYouLUI_iOS/YouYouLUI.xcodeproj -scheme YouYouLUI \
  -configuration Release -sdk iphonesimulator -destination "id=$DEVICE" \
  -derivedDataPath sim-build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-" ONLY_ACTIVE_ARCH=YES build
APP=sim-build/Build/Products/Release-iphonesimulator/YouYouLUI.app
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
mkdir -p native-check
xcodebuild test -project YouYouLUI_iOS/YouYouLUI.xcodeproj -scheme YouYouLUI \
  -configuration Release -sdk iphonesimulator -destination "id=$DEVICE" \
  -derivedDataPath sim-build -resultBundlePath native-check/ui-tests.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-" ONLY_ACTIVE_ARCH=YES
for SCENE in home-liquid settings-liquid settings-folded-liquid bottom-home-liquid bottom-separate-home-liquid dark-bottom-separate-home-liquid bottom-off-home-liquid; do
  case "$SCENE" in
    dark-*) APPEARANCE=dark ;;
    *) APPEARANCE=light ;;
  esac
  xcrun simctl ui "$DEVICE" appearance "$APPEARANCE"
  xcrun simctl install "$DEVICE" "$APP"
  DATA_DIR=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)
  rm -f "$DATA_DIR/Documents/ui-layout-verification.json"
  SIMCTL_CHILD_LUI_SNAPSHOT="$SCENE" xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID"
  for ATTEMPT in $(seq 1 180); do
    if [ -f "$DATA_DIR/Documents/ui-layout-verification.json" ]; then break; fi
    sleep 1
  done
  xcrun simctl io "$DEVICE" screenshot "native-check/$SCENE.png"
  if [ ! -f "$DATA_DIR/Documents/ui-layout-verification.json" ]; then
    echo "Native check did not finish: $SCENE"
    xcrun simctl spawn "$DEVICE" log show --last 5m --style compact --predicate 'process == "YouYouLUI"' > "native-check/$SCENE-runtime.log" || true
    cat "native-check/$SCENE-runtime.log"
    exit 1
  fi
  cp "$DATA_DIR/Documents/ui-layout-verification.json" "native-check/$SCENE.json"
  python3 - "$SCENE" "native-check/$SCENE.json" <<'PY'
import json, sys
scene, path = sys.argv[1:]
result = json.load(open(path))
assert result['passed'], result
assert result['appVersion'] == '1.0.4' and result['appBuild'] == '18', result
assert result['webContentInSelectedPage'], result
assert result.get('nativeSeparateSearch', False) == ('separate' in scene), result
if scene == 'settings-folded-liquid':
    assert not result['settingsScrollIndicator'], result
    assert result['documentHeight'] <= result['viewportHeight'] + 4, result
if scene == 'home-liquid':
    assert result['searchLiquid'] and not result['searchBlur'], result
if scene == 'bottom-home-liquid':
    assert result['nativeSearchEnabled'] and result['bottomSearchEnabled'], result
print('Native check passed:', scene)
PY
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID"
done
