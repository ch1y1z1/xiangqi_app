#!/bin/zsh
# Produce a device archive and an explicitly unsigned IPA for personal re-signing.
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-Debug}"
case "$configuration" in
    Debug|Release) ;;
    *) print -u2 'Usage: scripts/package-ipa.sh [Debug|Release]'; exit 2 ;;
esac

if [[ ! -f build/engine/position.h || ! -f Resources/pikafish.nnue ]]; then
    python3 scripts/prepare-engine.py
fi
python3 scripts/generate-project.py

archive_path="build/Archives/Xiangqi-${configuration}-unsigned.xcarchive"
xcodebuild -project Xiangqi.xcodeproj -scheme Xiangqi -configuration "$configuration" \
    -destination 'generic/platform=iOS' -derivedDataPath build/iOS \
    -archivePath "$archive_path" CODE_SIGNING_ALLOWED=NO \
    DEBUG_INFORMATION_FORMAT=dwarf-with-dsym archive

app_path="$archive_path/Products/Applications/Xiangqi.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Info.plist")"
artifact_dir="$(pwd)/build/ipa"
mkdir -p "$artifact_dir"
packaging_dir="$(mktemp -d "$artifact_dir/package.XXXXXX")"
trap 'rm -rf "$packaging_dir"' EXIT
mkdir "$packaging_dir/Payload"
ditto "$app_path" "$packaging_dir/Payload/Xiangqi.app"
ipa_path="$artifact_dir/Xiangqi-${version}-${configuration:l}-unsigned.ipa"
ditto -c -k --keepParent --norsrc --noextattr "$packaging_dir/Payload" "$ipa_path"
print "Unsigned device IPA: $ipa_path"
print 'Re-sign with your own iOS certificate and provisioning profile before installing.'
