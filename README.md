# Pearsnap

A lightweight macOS screenshot tool that captures, uploads, and shares in one flow. A tribute to [Skitch](https://en.wikipedia.org/wiki/Skitch_(software)) by Chris Pearson.

## Features

- **Quick Capture**: Press ⌘⇧5 to select any area of your screen
- **Instant Upload**: Automatically uploads to S3-compatible storage (DigitalOcean Spaces, AWS S3, etc.)
- **Auto-Copy**: URL copied to clipboard immediately after upload
- **Drag to Save**: Drag the preview to save the image anywhere
- **Upload History**: Access recent uploads from the menu bar
- **Launch at Login**: Optional auto-start

## Installation

1. Clone this repository
2. Open in Xcode or build with Swift Package Manager
3. Configure your S3 credentials in Settings

### Building

```bash
swift build
./build.sh  # Builds, signs, and deploys to /Applications
```

### Requirements

- macOS 13.0 or later
- S3-compatible storage (DigitalOcean Spaces, AWS S3, Backblaze B2, etc.)
- Apple Developer certificate (for code signing)

## Configuration

Open Pearsnap from the menu bar and click **Settings** to configure:

- **Endpoint**: Your S3 endpoint (e.g., `nyc3.digitaloceanspaces.com`)
- **Bucket Name**: Your bucket name
- **Region**: Your bucket region (e.g., `nyc3`)
- **Access Key**: Your S3 access key
- **Secret Key**: Your S3 secret key
- **Public URL Base**: The public URL prefix for your uploads

## Permissions

Pearsnap requires:
- **Accessibility**: For global keyboard shortcut
- **Screen Recording**: For capturing screenshots

## Why "Pearsnap"?

A tribute to Chris Pearson, creator of [Skitch](https://en.wikipedia.org/wiki/Skitch_(software)) — the beloved screenshot and annotation tool. Pearsnap carries forward the spirit of quick, effortless screen capture.

## License

MIT
