#!/bin/zsh
# Exercise the real app source factory on macOS without an iOS Simulator or live servers.
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
cd "$(dirname "$0")/.."
swift build --package-path BitChordKit -j "${JOBS:-2}"
QUEUE_PRODUCTS=$(swift build --package-path BitChordKit --show-bin-path)
QUEUE_MODULES="$QUEUE_PRODUCTS"
[ ! -d "$QUEUE_PRODUCTS/Modules" ] || QUEUE_MODULES="$QUEUE_PRODUCTS/Modules"
QUEUE_SCRATCH=$(mktemp -d)
trap 'rm -rf "$QUEUE_SCRATCH"' EXIT
QUEUE_OBJECTS=()
for module in BitChordCore AudioCache AudioDSP Playback PlaybackPolicy PlaybackQueue Sources StreamResolution Downloads; do
  if [ -f "$QUEUE_PRODUCTS/$module.o" ]; then
    QUEUE_OBJECTS+=("$QUEUE_PRODUCTS/$module.o")
  else
    QUEUE_OBJECTS+=("$QUEUE_PRODUCTS/$module.build/"*.o)
  fi
done
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" -I "$QUEUE_MODULES" \
  App/BitChord/Services/PlaybackSourceFactory.swift \
  App/BitChord/Services/SegmentedAudioSource.swift \
  App/BitChord/Services/DSPProcessor.swift \
  App/BitChord/Services/Deadline.swift \
  tests/playback/SourceQueueHarness.swift \
  "${QUEUE_OBJECTS[@]}" -o "$QUEUE_SCRATCH/source-queue-tests"
"$QUEUE_SCRATCH/source-queue-tests"
