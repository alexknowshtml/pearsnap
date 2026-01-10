# Pearsnap

A lightweight macOS screenshot tool that captures, uploads, and shares in one flow. A tribute to [Skitch](https://en.wikipedia.org/wiki/Skitch_(software)) by Chris Pearson.

## Features

- **Quick Capture**: Press ⌘⇧5 to select any area of your screen
- **Instant Upload**: Automatically uploads to S3-compatible storage (DigitalOcean Spaces, AWS S3, etc.)
- **Auto-Copy**: URL copied to clipboard immediately after upload
- **Drag to Save**: Drag the preview to save the image anywhere
- **Upload History**: Access recent uploads from the menu bar
- **Launch at Login**: Optional auto-start
- **Color Picker**: Loupe magnifier shows pixel colors with hex codes
- **Copy Hex**: Press ⌘C while hovering to copy the hex color to clipboard
- **Auto-Updates**: Built-in Sparkle updater checks for new versions

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧5 | Start capture |
| ESC | Cancel capture / Close preview |
| ⌘C | Copy hex color under cursor (during capture) |

## Installation

### Download

Download the latest release from the [Releases page](https://github.com/alexknowshtml/pearsnap/releases).

1. Download `Pearsnap-vX.X.X.zip`
2. Extract and move `Pearsnap.app` to `/Applications`
3. Launch and grant Accessibility + Screen Recording permissions when prompted
4. Configure your S3 credentials in Settings

**Note:** This is an unsigned build. You may need to right-click → Open the first time.

### Building from Source

```bash
./build.sh  # Builds, signs, and deploys to /Applications
```

Or manually:

```bash
swift build
cp .build/debug/Pearsnap Pearsnap.app/Contents/MacOS/Pearsnap
mkdir -p Pearsnap.app/Contents/Frameworks
cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework Pearsnap.app/Contents/Frameworks/
install_name_tool -add_rpath @executable_path/../Frameworks Pearsnap.app/Contents/MacOS/Pearsnap
codesign --force --deep --sign - Pearsnap.app
cp -R Pearsnap.app /Applications/
```

### Requirements

- macOS 13.0 or later
- S3-compatible storage (DigitalOcean Spaces, AWS S3, Backblaze B2, etc.)

## Configuration

Open Pearsnap from the menu bar and click **Settings** to configure:

- **Endpoint**: Your S3 endpoint (e.g., `nyc3.digitaloceanspaces.com`)
- **Bucket Name**: Your bucket name
- **Region**: Your bucket region (e.g., `nyc3`)
- **Access Key**: Your S3 access key
- **Secret Key**: Your S3 secret key
- **Public URL Base**: The public URL prefix for your uploads

Config stored at: `~/Library/Application Support/Pearsnap/config.json`

## Permissions

Pearsnap requires:
- **Accessibility**: For global keyboard shortcut
- **Screen Recording**: For capturing screenshots

## Releasing New Versions

To release a new version:

```bash
./release.sh 1.2.0
```

This single command will:
1. Bump version in Info.plist
2. Build the app with Sparkle framework
3. Create and sign the release zip with EdDSA
4. Create a GitHub release with the zip attached
5. Update `docs/appcast.xml` with the new version
6. Commit and push everything

Users with Pearsnap installed can then click **Check for Updates...** in the menu to get the new version.

### Manual Release Steps

If you need to release manually:

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Pearsnap.app/Contents/Info.plist`
2. Run `./build.sh`
3. Create zip: `zip -r Pearsnap-vX.X.X.zip Pearsnap.app`
4. Sign: `~/.build/artifacts/sparkle/Sparkle/bin/sign_update Pearsnap-vX.X.X.zip -f ~/Developer/Pearsnap/sparkle_private_key`
5. Create GitHub release and attach the zip
6. Add new `<item>` to `docs/appcast.xml` with the signature
7. Push to main

## Why "Pearsnap"?

A tribute to Chris Pearson, creator of [Skitch](https://en.wikipedia.org/wiki/Skitch_(software)) — the beloved screenshot and annotation tool. Pearsnap carries forward the spirit of quick, effortless screen capture.

## License

MIT
