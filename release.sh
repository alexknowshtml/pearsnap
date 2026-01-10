#!/bin/bash
set -e

cd "$(dirname "$0")"

# Check for version argument
if [ -z "$1" ]; then
    echo "Usage: ./release.sh <version>"
    echo "Example: ./release.sh 1.1.0"
    exit 1
fi

VERSION=$1
BUILD_NUM=$(($(grep -A1 CFBundleVersion Pearsnap.app/Contents/Info.plist | grep string | sed 's/[^0-9]//g') + 1))

echo "=== Releasing Pearsnap v$VERSION (build $BUILD_NUM) ==="

# Step 1: Update Info.plist
echo "Updating version in Info.plist..."
sed -i '' "s/<string>[0-9]*\.[0-9]*\.[0-9]*<\/string>/<string>$VERSION<\/string>/" Pearsnap.app/Contents/Info.plist
sed -i '' "s/<key>CFBundleVersion<\/key>.*<string>[0-9]*<\/string>/<key>CFBundleVersion<\/key>\n\t<string>$BUILD_NUM<\/string>/" Pearsnap.app/Contents/Info.plist

# Step 2: Build
echo "Building..."
./build.sh

# Step 3: Create zip
echo "Creating zip..."
ZIP_NAME="Pearsnap-v$VERSION.zip"
rm -f "$ZIP_NAME"
zip -r "$ZIP_NAME" Pearsnap.app

# Step 4: Sign
echo "Signing release..."
SIGNATURE=$(~/.build/artifacts/sparkle/Sparkle/bin/sign_update "$ZIP_NAME" -f ~/Developer/Pearsnap/sparkle_private_key 2>&1)
echo "$SIGNATURE"

# Extract just the signature value
ED_SIG=$(echo "$SIGNATURE" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGNATURE" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

if [ -z "$ED_SIG" ]; then
    echo "ERROR: Failed to get signature"
    exit 1
fi

# Step 5: Create GitHub release
echo "Creating GitHub release..."
gh release create "v$VERSION" "$ZIP_NAME" \
    --title "Pearsnap v$VERSION" \
    --notes "Release v$VERSION"

# Step 6: Update appcast.xml
echo "Updating appcast.xml..."
PUBDATE=$(date -R)
NEW_ITEM="        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUBDATE</pubDate>
            <sparkle:version>$BUILD_NUM</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <description><![CDATA[
                <h2>Version $VERSION</h2>
                <p>See release notes on GitHub.</p>
            ]]></description>
            <enclosure url=\"https://github.com/alexknowshtml/pearsnap/releases/download/v$VERSION/$ZIP_NAME\"
                       sparkle:edSignature=\"$ED_SIG\"
                       length=\"$LENGTH\"
                       type=\"application/octet-stream\"/>
        </item>"

# Insert new item after <language>en</language>
sed -i '' "/<language>en<\/language>/a\\
$NEW_ITEM
" docs/appcast.xml

# Step 7: Commit and push
echo "Committing and pushing..."
git add -A
git commit --no-gpg-sign -m "Release v$VERSION"
git push

# Cleanup
rm -f "$ZIP_NAME"

echo ""
echo "=== Released Pearsnap v$VERSION ==="
echo "GitHub: https://github.com/alexknowshtml/pearsnap/releases/tag/v$VERSION"
echo "Appcast: https://alexknowshtml.github.io/pearsnap/appcast.xml"
