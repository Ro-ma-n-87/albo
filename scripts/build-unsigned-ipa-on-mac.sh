#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# This creates a real device build, never a renamed Simulator archive.
# The result is deliberately unsigned and must be signed before installation.
if [ "$(uname -s)" != "Darwin" ]; then
  echo "Ein IPA-Build benötigt macOS mit Xcode. Unter Windows kann dieser Build nicht ausgeführt werden."
  exit 1
fi
command -v xcodebuild >/dev/null
xcodebuild -version

OUTPUT_DIR="$PWD/build/ipa"
DERIVED_DIR="$PWD/build/DeviceDerivedData"
mkdir -p "$OUTPUT_DIR"

xcodebuild \
  -project ALBOConnect.xcodeproj \
  -scheme ALBOConnect \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  build

APP="$DERIVED_DIR/Build/Products/Release-iphoneos/ALBOConnect.app"
if [ ! -d "$APP" ]; then
  echo "Der Geräte-Build hat keine ALBOConnect.app erzeugt. Es wird keine IPA erstellt."
  exit 1
fi

PLIST="$APP/Info.plist"
EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")
PLATFORM=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$PLIST")
if [ "$PLATFORM" != "iPhoneOS" ]; then
  echo "Kein iPhone-Geräte-Build. Eine Simulator-App darf nicht als Geräte-IPA verpackt werden."
  exit 1
fi
if ! xcrun lipo -archs "$APP/$EXECUTABLE" | grep -qw arm64; then
  echo "Die ausführbare Datei enthält keinen arm64-Gerätecode."
  exit 1
fi
if ! xcrun vtool -show-build "$APP/$EXECUTABLE" | grep -Eq 'platform[[:space:]]+IOS[[:space:]]*$'; then
  echo "Die Mach-O-Plattform ist nicht iOS. Es wird keine IPA erstellt."
  exit 1
fi

STAGE=$(mktemp -d "$PWD/build/ipa-stage.XXXXXX")
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/ALBOConnect.app"
IPA="$OUTPUT_DIR/ALBOConnect-unsigned.ipa"
ditto -c -k --keepParent "$STAGE/Payload" "$IPA"

# Validate the ZIP contents as well as the original app bundle.
python3 - "$IPA" <<'PY'
import hashlib, json, pathlib, plistlib, sys, zipfile
ipa = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(ipa) as archive:
    names = set(archive.namelist())
    plist_name = 'Payload/ALBOConnect.app/Info.plist'
    if plist_name not in names:
        raise SystemExit('IPA enthält keinen gültigen Payload/ALBOConnect.app-Ordner.')
    info = plistlib.loads(archive.read(plist_name))
    binary = 'Payload/ALBOConnect.app/' + info['CFBundleExecutable']
    if binary not in names or archive.getinfo(binary).file_size == 0:
        raise SystemExit('Die IPA enthält keine ausführbare App-Datei.')
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise SystemExit('Die IPA enthält keinen iPhone-Geräte-Build.')
    if any(name.endswith('embedded.mobileprovision') for name in names):
        raise SystemExit('Der unsignierte Build enthält unerwartet ein Provisioning-Profil.')
summary = {
    'file': ipa.name,
    'platform': 'iOS device',
    'architecture': 'arm64',
    'signed': False,
    'installable_without_signing': False,
    'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
}
(ipa.parent / 'IPA-STATUS.json').write_text(json.dumps(summary, indent=2) + '\n')
(ipa.parent / 'BITTE-LESEN.txt').write_text(
    'ALBO Connect: echter iPhone-/iPad-Geräte-Build, noch ohne Apple-Signierung.\n'
    'Diese IPA lässt sich nicht direkt auf einem normalen iPhone installieren.\n'
    'Vor der Installation sind eine eigene gültige Signierung und passende Gerätebereitstellung erforderlich.\n'
)
print(json.dumps(summary))
PY
