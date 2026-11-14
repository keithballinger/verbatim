#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcodebuild -project Verbatim.xcodeproj -scheme Verbatim -configuration Debug \
  -derivedDataPath .build -destination 'platform=macOS' test "$@"
