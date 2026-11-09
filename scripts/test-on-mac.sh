#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -version
plutil -lint ALBOConnect/Info.plist ALBOConnect/PrivacyInfo.xcprivacy ALBOConnect.xcodeproj/project.pbxproj
SIMULATOR_ID="${SIMULATOR_ID:-$(xcrun simctl list devices available -j | python3 -c 'import json,sys; ds=json.load(sys.stdin)["devices"]; phones=[d["udid"] for k,v in ds.items() if "iOS" in k for d in v if "iPhone" in d["name"]]; print(phones[0] if phones else "")')}"
if [ -z "$SIMULATOR_ID" ]; then
  echo "Kein iPhone-Simulator installiert. In Xcode unter Settings > Components einen iOS-Simulator installieren."
  exit 1
fi
xcodebuild -project ALBOConnect.xcodeproj -scheme ALBOConnect -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath build/DerivedData -resultBundlePath "build/Tests-$(date +%Y%m%d-%H%M%S).xcresult" CODE_SIGNING_ALLOWED=NO test
