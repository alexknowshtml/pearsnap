import AppKit
import ScreenCaptureKit

protocol CaptureManagerDelegate: AnyObject {
    func captureManagerDidUpload(url: String)
}

class CaptureManager: NSObject {
    weak var delegate: CaptureManagerDelegate?
    private var previewWindow: PreviewWindow?
    private var currentTempFile: String?
    private var captureScreen: NSScreen?
    
    func startCapture() {
        cleanupPreview()
        
        // Remember which screen the mouse is on
        let mouseLocation = NSEvent.mouseLocation
        captureScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        
        let tempFile = NSTemporaryDirectory() + "snapclone_\(Int(Date().timeIntervalSince1970)).png"
        currentTempFile = tempFile
        
        task.arguments = ["-i", "-s", "-x", tempFile]
        
        task.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if process.terminationStatus == 0 {
                    if let image = NSImage(contentsOfFile: tempFile) {
                        self.showPreviewAndUpload(image: image, tempFile: tempFile)
                    } else {
                        self.cleanupTempFile(tempFile)
                    }
                } else {
                    self.cleanupTempFile(tempFile)
                }
            }
        }
        
        do {
            try task.run()
        } catch {
            print("Failed to run screencapture: \(error)")
            cleanupTempFile(tempFile)
        }
    }
    
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
    
    private func showPreviewAndUpload(image: NSImage, tempFile: String) {
        // Show preview window
        let preview = PreviewWindow(image: image, screen: captureScreen)
        previewWindow = preview
        currentTempFile = tempFile
        
        preview.onClose = { [weak self] in
            if let tf = self?.currentTempFile {
                self?.cleanupTempFile(tf)
                self?.currentTempFile = nil
            }
        }
        
        preview.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Start upload automatically
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
                    // Copy to clipboard
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    
                    // Add to history
                    let filename = URL(string: url)?.lastPathComponent ?? "screenshot.png"
                    HistoryManager.shared.add(url: url, filename: filename)
                    
                    // Update menu
                    self?.delegate?.captureManagerDidUpload(url: url)
                    
                    // Show success in preview
                    self?.previewWindow?.showSuccess(url: url)
                    
                case .failure(let error):
                    self?.previewWindow?.showError(error.localizedDescription)
                }
            }
        }
    }
}
