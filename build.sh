#!/bin/bash
set -e

cd "$(dirname "$0")"

# TODO: For stable permissions, run this build locally (not via SSH) 
# with: SIGNING_IDENTITY="Apple Development: Alex Hillman (6VCY6GJAPH)"
# Ad-hoc signing works but requires re-granting permissions after each rebuild
SIGNING_IDENTITY="Apple Development: Alex Hillman (6VCY6GJAPH)"

echo "Building Pearsnap..."
swift build

echo "Updating app bundle..."
cp .build/debug/Pearsnap Pearsnap.app/Contents/MacOS/Pearsnap

echo "Copying Sparkle framework..."
mkdir -p Pearsnap.app/Contents/Frameworks
cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework Pearsnap.app/Contents/Frameworks/

echo "Adding framework rpath..."
install_name_tool -add_rpath @executable_path/../Frameworks Pearsnap.app/Contents/MacOS/Pearsnap 2>/dev/null || true

echo "Re-signing app..."
codesign --force --deep --sign "$SIGNING_IDENTITY" Pearsnap.app

echo "Deploying to /Applications..."
pkill -f Pearsnap.app/Contents/MacOS/Pearsnap 2>/dev/null || true
sleep 0.5
cp -R Pearsnap.app /Applications/

echo "Done! Run: open /Applications/Pearsnap.app"
echo ""
echo "NOTE: For permissions to persist across builds, run build.sh"
echo "directly on Mac Mini (not via SSH) and change SIGNING_IDENTITY"
echo "to your Developer certificate."
