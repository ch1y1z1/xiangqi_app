#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

platform="${1:-mac}"
if [[ ! -f build/engine/position.h || ! -f Resources/pikafish.nnue ]]; then
    python3 scripts/prepare-engine.py
fi
python3 scripts/generate-project.py

case "$platform" in
    mac)
        xcodebuild -project Xiangqi.xcodeproj -scheme Xiangqi -destination 'platform=macOS' \
            -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
        codesign --force --sign - build/DerivedData/Build/Products/Debug/Xiangqi.app
        ;;
    ios)
        xcodebuild -project Xiangqi.xcodeproj -scheme Xiangqi -destination 'generic/platform=iOS' \
            -derivedDataPath build/iOS CODE_SIGNING_ALLOWED=NO build
        ;;
    sim)
        xcodebuild -project Xiangqi.xcodeproj -scheme Xiangqi -destination 'generic/platform=iOS Simulator' \
            -derivedDataPath build/Simulator CODE_SIGNING_ALLOWED=NO build
        codesign --force --sign - build/Simulator/Build/Products/Debug-iphonesimulator/Xiangqi.app
        ;;
    *)
        print -u2 'Usage: scripts/build.sh [mac|ios|sim]'
        exit 2
        ;;
esac
