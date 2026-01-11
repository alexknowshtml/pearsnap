import AppKit
import AudioToolbox

protocol CaptureManagerDelegate: AnyObject {
    func captureManagerDidUpload(url: String)
}

class CaptureManager: NSObject, SelectionOverlayDelegate {
    weak var delegate: CaptureManagerDelegate?
    private var previewWindow: PreviewWindow?
    private var currentTempFile: String?
    private var captureScreen: NSScreen?
    private var selectionOverlays: [SelectionOverlay] = []
    private var screenSnapshots: [NSScreen: CGImage] = [:]  // Pre-captured snapshots
    
    func startCapture() {
        cleanupPreview()
        showSelectionOverlay()
    }

    func captureFullscreen() {
        cleanupPreview()

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main else {
            return
        }

        captureScreen = screen

        let screenFrame = screen.frame
        let cgRect = CGRect(
            x: screenFrame.origin.x,
            y: 0,
            width: screenFrame.width,
            height: screenFrame.height
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let cgImage = CGWindowListCreateImage(
                cgRect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                .bestResolution
            ) else {
                print("Failed to capture fullscreen")
                return
            }

            AudioServicesPlaySystemSound(1108)

            let image = NSImage(cgImage: cgImage, size: screenFrame.size)
            self?.showPreviewAndUpload(image: image)
        }
    }

    func captureWindow() {
        cleanupPreview()

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        let windows = windowList.filter { info in
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width > 50 && height > 50,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else {
                return false
            }
            return true
        }

        guard !windows.isEmpty else { return }

        let targetWindow = windows.first { info in
            let ownerName = info[kCGWindowOwnerName as String] as? String
            return ownerName != "Pearsnap"
        } ?? windows.first

        guard let windowInfo = targetWindow,
              let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
              let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
              let x = boundsDict["X"], let y = boundsDict["Y"],
              let width = boundsDict["Width"], let height = boundsDict["Height"] else {
            return
        }

        let bounds = CGRect(x: x, y: y, width: width, height: height)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let cgImage = CGWindowListCreateImage(
                bounds,
                .optionIncludingWindow,
                windowID,
                [.bestResolution, .boundsIgnoreFraming]
            ) else {
                print("Failed to capture window")
                return
            }

            AudioServicesPlaySystemSound(1108)

            let image = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
            self?.showPreviewAndUpload(image: image)
        }
    }

    private func showSelectionOverlay() {
        // Close any existing overlays
        selectionOverlays.forEach { $0.close() }
        selectionOverlays.removeAll()
        screenSnapshots.removeAll()
        
        // CRITICAL: Capture all screen snapshots BEFORE creating any overlays
        for screen in NSScreen.screens {
            if let snapshot = captureScreenSnapshot(for: screen) {
                screenSnapshots[screen] = snapshot
            }
        }
        
        // Find screen with mouse
        let mouseLocation = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        
        // Activate app FIRST, before creating windows
        NSApp.activate(ignoringOtherApps: true)
        
        // Small delay to ensure activation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            
            // Create overlay for each screen with pre-captured snapshot
            for screen in NSScreen.screens {
                let snapshot = self.screenSnapshots[screen]
                let overlay = SelectionOverlay(screen: screen, snapshot: snapshot)
                overlay.selectionDelegate = self
                
                // Show all overlays
                overlay.orderFront(nil)
                self.selectionOverlays.append(overlay)
            }
            
            // Make the overlay with the mouse the key window AFTER all are created
            if let keyOverlay = self.selectionOverlays.first(where: { $0.overlayScreen == mouseScreen }) {
                keyOverlay.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    private func captureScreenSnapshot(for screen: NSScreen) -> CGImage? {
        let screenRect = CGRect(
            x: screen.frame.origin.x,
            y: NSScreen.screens[0].frame.height - screen.frame.origin.y - screen.frame.height,
            width: screen.frame.width,
            height: screen.frame.height
        )
        
        return CGWindowListCreateImage(
            screenRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        )
    }
    
    // MARK: - SelectionOverlayDelegate
    
    func selectionOverlay(_ overlay: SelectionOverlay, didSelectRegion rect: CGRect, screen: NSScreen) {
        // Get the pre-captured snapshot for this screen
        let snapshot = screenSnapshots[screen]
        
        // Close all overlays
        selectionOverlays.forEach { $0.close() }
        selectionOverlays.removeAll()
        
        captureScreen = screen
        
        // Use the pre-captured snapshot - no timing issues!
        captureScreenshot(rect: rect, screen: screen, snapshot: snapshot)
    }
    
    func selectionOverlayCancelled(_ overlay: SelectionOverlay) {
        selectionOverlays.forEach { $0.close() }
        selectionOverlays.removeAll()
        screenSnapshots.removeAll()
    }
    
    // MARK: - Screenshot Capture
    
    private func captureScreenshot(rect: CGRect, screen: NSScreen, snapshot: CGImage?) {
        let cgImage: CGImage?
        
        if let snapshot = snapshot {
            // Use the pre-captured snapshot and crop to selection
            let scale = CGFloat(snapshot.width) / screen.frame.width
            
            // Convert selection rect to snapshot coordinates
            let localX = rect.origin.x - screen.frame.origin.x
            let localY = rect.origin.y - screen.frame.origin.y
            
            let cropRect = CGRect(
                x: localX * scale,
                y: (screen.frame.height - localY - rect.height) * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
            
            cgImage = snapshot.cropping(to: cropRect)
        } else {
            // Fallback: capture fresh (shouldn't happen normally)
            let cgRect = CGRect(
                x: rect.origin.x,
                y: NSScreen.screens[0].frame.height - rect.origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )
            
            cgImage = CGWindowListCreateImage(
                cgRect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                .bestResolution
            )
        }
        
        guard let finalImage = cgImage else {
            print("Failed to capture screenshot")
            screenSnapshots.removeAll()
            return
        }
        
        // Clean up snapshots
        screenSnapshots.removeAll()
        
        // Play capture sound
        AudioServicesPlaySystemSound(1108)

        let image = NSImage(cgImage: finalImage, size: rect.size)
        showPreviewAndUpload(image: image)
    }
    
    // MARK: - Preview & Upload
    
    private func cleanupPreview() {
        if let window = previewWindow {
            window.onClose = nil
            window.orderOut(nil)
            previewWindow = nil
        }
        if let tempFile = currentTempFile {
            cleanupTempFile(tempFile)
            currentTempFile = nil
        }
    }
    
    private func cleanupTempFile(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
    
    private func showPreviewAndUpload(image: NSImage) {
        let preview = PreviewWindow(image: image, screen: captureScreen)
        previewWindow = preview
        
        preview.onClose = { [weak self] in
            if let tf = self?.currentTempFile {
                self?.cleanupTempFile(tf)
                self?.currentTempFile = nil
            }
        }
        
        preview.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        preview.showUploading()
        uploadImage(image)
    }
    
    private func uploadImage(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            print("Failed to convert image to PNG")
            previewWindow?.showError("Failed to process image")
            return
        }
        
        S3Uploader.shared.upload(data: pngData) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)

                    let filename = URL(string: url)?.lastPathComponent ?? "screenshot.png"
                    HistoryManager.shared.add(url: url, filename: filename, image: image)

                    self?.delegate?.captureManagerDidUpload(url: url)
                    self?.previewWindow?.showSuccess(url: url)

                case .failure(let error):
                    self?.previewWindow?.showError(error.localizedDescription)
                }
            }
        }
    }
}
