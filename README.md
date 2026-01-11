# Pearsnap

A lightweight macOS screenshot tool that captures, uploads, and shares in one flow. A tribute to [Skitch](https://en.wikipedia.org/wiki/Skitch_(software)) by Chris Pearson.

## Features

- **Quick Capture**: Press ⌘⇧5 to select any area of your screen
- **Instant Upload**: Automatically uploads to S3-compatible storage (DigitalOcean Spaces, AWS S3, etc.)
- **Auto-Copy**: URL copied to clipboard immediately after upload
- **Drag to Save**: Drag the preview to save the image anywhere (preview slides to corner while dragging)
- **Redaction Tool**: Pixelate sensitive information before sharing
- **Upload History**: Access recent uploads from the menu bar with navigation
- **Color Picker**: Loupe magnifier shows pixel colors with hex codes
- **Copy Hex**: Press ⌘C while hovering to copy the hex color to clipboard
- **Cmd+Tab Support**: Preview window appears in app switcher
- **Launch at Login**: Optional auto-start
- **Auto-Updates**: Built-in Sparkle updater checks for new versions

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧5 | Start capture |
| ESC | Cancel capture / Close preview / Exit redact mode |
| ⌘C | Copy hex color under cursor (during capture) |
| ← → | Navigate upload history (in preview) |

## Preview Window

After capturing, the preview window lets you:
- **Drag** the image to save it anywhere (Finder, apps, desktop)
- **Navigate** through recent uploads with arrow keys or buttons
- **Redact** sensitive info by clicking the eye icon, drawing rectangles, then clicking ✓
- **Cmd+Tab** back to the preview if you switch away

The preview slides to the nearest corner while you're dragging, then returns when you drop.

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

For permissions to persist across rebuilds, sign with your Developer certificate:
```bash
# Edit build.sh and set SIGNING_IDENTITY to your certificate
./build.sh
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

If permissions get stuck after a rebuild, click **Reset Permissions & Relaunch** in the setup window, or run:
```bash
./reset-permissions.sh
```

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

## Why "Pearsnap"?

A tribute to Chris Pearson, creator of [Skitch](https://en.wikipedia.org/wiki/Skitch_(software)) — the beloved screenshot and annotation tool. Pearsnap carries forward the spirit of quick, effortless screen capture.

## License

MIT
