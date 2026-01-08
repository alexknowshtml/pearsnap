#\!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building Pearsnap..."
swift build

echo "Updating app bundle..."
cp .build/debug/Pearsnap Pearsnap.app/Contents/MacOS/Pearsnap

echo "Signing app with Developer certificate..."
codesign --force --deep --sign "Apple Development: Alex Hillman (6VCY6GJAPH)" Pearsnap.app

echo "Deploying to /Applications..."
pkill -f Pearsnap.app/Contents/MacOS/Pearsnap 2>/dev/null || true
pkill -f SnapClone.app/Contents/MacOS/SnapClone 2>/dev/null || true
sleep 0.5
cp -R Pearsnap.app /Applications/

echo "Done\! Run: open /Applications/Pearsnap.app"
