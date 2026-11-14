#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcodebuild -project Verbatim.xcodeproj -scheme Verbatim -configuration Release \
  -derivedDataPath .build ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build "$@"
