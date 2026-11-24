#!/bin/zsh
# Build a Release IPA for testers to sideload (AltStore, SideStore, Sideloadly, …): the app and its
# two extensions, ad-hoc signed with their entitlements so the sideloader re-signs them with the
# tester's own Apple ID and remaps the shared app group. No Apple Developer account is needed here.
#   scripts/make-ipa.sh            → build/BitChord-<version>.ipa
# JOBS=n caps parallel compile jobs (default 3), as in the other scripts.
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
cd "$(dirname "$0")/.."

python3 scripts/apply-korean.py
MIN_IOS=17.0 SDK_NAME=iphoneos bash WireGuard/build-ios.sh

DERIVED=.derived-release
env -u LASTFM_API_KEY -u LASTFM_API_SECRET xcodebuild build -workspace BitChord.xcworkspace -scheme BitChord -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" -jobs "${JOBS:-3}" -quiet \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

APP="$DERIVED/Build/Products/Release-iphoneos/BitChord.app"
[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Info.plist")

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
STAGED="$STAGE/Payload/BitChord.app"

# Optional Last.fm credentials belong in the signed bundle. Keep them out of
# command arguments and Xcode's build settings output.
python3 - "$STAGED/Info.plist" <<'PYPLIST'
import os
import plistlib
import sys
from pathlib import Path

names = ("LASTFM_API_KEY", "LASTFM_API_SECRET")
values = {name: os.environ.get(name, "").strip() for name in names}
if any(values.values()):
    if not all(values.values()):
        raise SystemExit("Both Last.fm credentials are required.")
    info = Path(sys.argv[1])
    with info.open("rb") as source:
        plist = plistlib.load(source)
    plist.update(values)
    with info.open("wb") as destination:
        plistlib.dump(plist, destination, fmt=plistlib.FMT_BINARY)
    print("Last.fm credentials included in the IPA.")
PYPLIST

# A prior build-for-testing can leave a test bundle in the shared product directory.
# It must never ship in a sideload IPA, even when a normal build did not clean it up.
find "$STAGED" -type d -name '*.xctest' -prune -exec rm -rf {} \;

# Inside out: embedded frameworks, then each extension with its entitlements, then the app.
find "$STAGED" -name "*.framework" -type d -prune | while read -r fw; do
  codesign --force --sign - --timestamp=none "$fw"
done
codesign --force --sign - --timestamp=none --entitlements App/Config/BitChordWidget.entitlements \
  "$STAGED/PlugIns/BitChordWidgetExtension.appex"
codesign --force --sign - --timestamp=none --entitlements App/Config/BitChordShare.entitlements \
  "$STAGED/PlugIns/BitChordShareExtension.appex"
codesign --force --sign - --timestamp=none --entitlements App/Config/BitChord.entitlements "$STAGED"

mkdir -p build
OUT="build/BitChord-$VERSION.ipa"
rm -f "$OUT"
(cd "$STAGE" && zip -qry - Payload) > "$OUT"
echo "$OUT ($(du -h "$OUT" | cut -f1))"
scripts/verify-ipa.sh "$OUT"
