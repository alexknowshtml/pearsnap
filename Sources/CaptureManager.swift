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
    
    func startCapture() {
        cleanupPreview()
        showSelectionOverlay()
    }

    func captureFullscreen() {
        cleanupPreview()

        // Get the screen with the mouse
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main else {
            return
        }

        captureScreen = screen

        // Capture the entire screen
        let screenFrame = screen.frame
        let cgRect = CGRect(
            x: screenFrame.origin.x,
            y: 0,  // CGWindowListCreateImage uses top-left origin
            width: screenFrame.width,
            height: screenFrame.height
        )

        // Small delay to let menu close
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

        // Get list of windows
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        // Filter to windows that have a name and reasonable size
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

        // Use the frontmost window (first in list after current app)
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

        // Small delay to let menu close
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
        // Find screen with mouse
        let mouseLocation = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        
        // Close any existing overlays
        selectionOverlays.forEach { $0.close() }
        selectionOverlays.removeAll()
        
        // Create overlay for each screen
        for screen in NSScreen.screens {
            let overlay = SelectionOverlay(screen: screen)
            overlay.selectionDelegate = self
            
            // Only make the overlay with the mouse the key window
            if screen == mouseScreen {
                overlay.makeKeyAndOrderFront(nil)
            } else {
                overlay.orderFront(nil)
            }
            selectionOverlays.append(overlay)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        // Ensure the correct overlay is key after activation
        if let keyOverlay = selectionOverlays.first(where: { $0.screen == mouseScreen }) {
            keyOverlay.makeKey()
        }
    }
    
    // MARK: - SelectionOverlayDelegate
    
    func selectionOverlay(_ overlay: SelectionOverlay, didSelectRegion rect: CGRect, screen: NSScreen) {
        // Close all overlays
        selectionOverlays.forEach { $0.close() }
        selectionOverlays.removeAll()
        
        captureScreen = screen
        captureScreenshot(rect: rect, screen: screen)
    }
    
    func selectionOverlayCancelled(_ overlay: SelectionOverlay) {
        selectionOverlays.forEach { $0.close() }
        selectionOverlays.removeAll()
    }
    
    // MARK: - Screenshot Capture
    
    private func captureScreenshot(rect: CGRect, screen: NSScreen) {
        // Convert to screen coordinates for CGWindowListCreateImage
        let cgRect = CGRect(
            x: rect.origin.x,
            y: NSScreen.screens[0].frame.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        
        guard let cgImage = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenBelowWindow,
            kCGNullWindowID,
            .bestResolution
        ) else {
            print("Failed to capture screenshot")
            return
        }
        
        // Play capture sound
        AudioServicesPlaySystemSound(1108)  // Screen capture sound

        let image = NSImage(cgImage: cgImage, size: rect.size)
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
