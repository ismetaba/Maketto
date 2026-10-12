#!/usr/bin/env bash
# Build the Debug app and photograph every DEBUG demo screen (see
# Sources/App/DemoLaunch.swift) on a large and a small iPhone, light + dark.
set -euo pipefail
OUT=${1:-screenshots}
mkdir -p "$OUT"
BUNDLE=com.matt.maketto
SCREENS=(list empty about scan scanReview home homeRoom home3D room room3D edit editFurniture editWall catalog creator versions)
DEVICES=("iPhone 16 Pro:pro" "iPhone SE (3rd generation):se")

xcodebuild build -project Maketto.xcodeproj -scheme Maketto -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO -quiet
APP=build/Build/Products/Debug-iphonesimulator/Maketto.app

for entry in "${DEVICES[@]}"; do
  NAME=${entry%%:*}; TAG=${entry##*:}
  UDID=$(python3 scripts/find-simulator.py "$NAME") || { echo "skip $NAME"; continue; }
  xcrun simctl boot "$UDID" || true
  xcrun simctl bootstatus "$UDID" -b
  xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active \
    --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
  xcrun simctl install "$UDID" "$APP"
  for MODE in light dark; do
    xcrun simctl ui "$UDID" appearance "$MODE"
    for S in "${SCREENS[@]}"; do
      xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
      xcrun simctl launch "$UDID" "$BUNDLE" -uiDemo "$S" >/dev/null
      sleep 6
      FILE="$OUT/$TAG-$MODE-$S.png"
      xcrun simctl io "$UDID" screenshot "$FILE" >/dev/null 2>&1
      sips -Z 1000 "$FILE" >/dev/null
      echo "shot $FILE"
    done
  done
  xcrun simctl shutdown "$UDID" || true
done
