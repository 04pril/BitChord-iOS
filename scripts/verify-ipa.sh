#!/bin/bash
# Check a sideload IPA the way a sideloader will read it: the signature verifies, and the app and
# each extension carry the app-group entitlement (the sideloader remaps it; without it the widget
# and share extension can't see the app's data). Prints the signature and entitlements for the log.
#   scripts/verify-ipa.sh build/BitChord-<version>.ipa
set -euo pipefail
IPA=${1:?usage: verify-ipa.sh <ipa>}
[ -f "$IPA" ] || { echo "no IPA at $IPA" >&2; exit 1; }

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
ditto -x -k "$IPA" "$DIR"
APP="$DIR/Payload/BitChord.app"
[ -d "$APP" ] || { echo "$IPA has no Payload/BitChord.app" >&2; exit 1; }
python3 - "$APP" <<'PYVERIFY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
tests = list(app.rglob('*.xctest'))
if tests:
    raise SystemExit('test bundles must not ship: ' + ', '.join(str(p.relative_to(app)) for p in tests))
def info(bundle):
    with (bundle / 'Info.plist').open('rb') as stream:
        return plistlib.load(stream)
main = info(app)
for extension in (app / 'PlugIns').glob('*.appex'):
    values = info(extension)
    for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
        if values.get(key) != main.get(key):
            raise SystemExit(f'{extension.name}: {key} does not match the app')
print(f'IPA version verified: {main["CFBundleShortVersionString"]} ({main["CFBundleVersion"]}), no test bundles')
PYVERIFY

# --deep covers the extensions and frameworks; --strict rejects a bundle changed after signing.
codesign --verify --deep --strict --verbose=2 "$APP"
for b in "$APP" "$APP"/PlugIns/*.appex; do
  echo "== $(basename "$b")"
  codesign -dv "$b" 2>&1 | grep -E '^(Identifier|Signature|Format)=' || true
  ENT=$(codesign -d --entitlements :- "$b" 2>/dev/null)
  echo "$ENT"
  grep -q "group.com.music.bitchord" <<<"$ENT" \
    || { echo "$(basename "$b") lacks the app-group entitlement" >&2; exit 1; }
done
