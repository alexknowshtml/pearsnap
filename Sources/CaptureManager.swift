import AppKit
import ScreenCaptureKit

protocol CaptureManagerDelegate: AnyObject {
    func captureManagerDidUpload(url: String)
}

class CaptureManager: NSObject, SelectionOverlayDelegate {
    weak var delegate: CaptureManagerDelegate?
    private var previewWindow: PreviewWindow?
    private var currentTempFile: String?
    private var captureScreen: NSScreen?
    private var selectionOverlays: [SelectionOverlay] = []
    private var videoRecorder: VideoRecorder?
    private var isRecordingVideo = false
    private var recordingIndicator: RecordingIndicatorWindow?
    
    func startCapture() {
        cleanupPreview()
        showSelectionOverlay()
    }
    
    private func showSelectionOverlay() {
        // Close any existing overlays
        selectionOverlays.forEach { $0.close() }
        selectionOverlays.removeAll()
        
        // Create overlay for each screen
        for screen in NSScreen.screens {
            let overlay = SelectionOverlay(screen: screen)
            overlay.selectionDelegate = self
            overlay.makeKeyAndOrderFront(nil)
            selectionOverlays.append(overlay)
        }
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - SelectionOverlayDelegate
    
    func selectionOverlay(_ overlay: SelectionOverlay, didSelectRegion rect: CGRect, mode: CaptureMode, screen: NSScreen) {
        // Close all overlays
        selectionOverlays.forEach { $0.close() }
        selectionOverlays.removeAll()
        
        captureScreen = screen
        
        switch mode {
        case .screenshot:
            captureScreenshot(rect: rect, screen: screen)
        case .video:
            startVideoRecording(rect: rect, screen: screen)
        }
    }
    
    func selectionOverlayCancelled(_ overlay: SelectionOverlay) {
        selectionOverlays.forEach { $0.close() }
        selectionOverlays.removeAll()
    }
    
    // MARK: - Screenshot Capture
    
    private func captureScreenshot(rect: CGRect, screen: NSScreen) {
        // Convert to screen coordinates for CGWindowListCreateImage
        let screenFrame = screen.frame
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
        
        let image = NSImage(cgImage: cgImage, size: rect.size)
        showPreviewAndUpload(image: image)
    }
    
    // MARK: - Video Recording
    
    private func startVideoRecording(rect: CGRect, screen: NSScreen) {
        isRecordingVideo = true
        videoRecorder = VideoRecorder()
        
        // Show recording indicator
        showRecordingIndicator(for: rect)
        
        Task {
            do {
                let outputURL = try await videoRecorder!.startRecording(region: rect, screen: screen)
                print("Recording started: \(outputURL)")
            } catch {
                print("Failed to start recording: \(error)")
                await MainActor.run {
                    hideRecordingIndicator()
                    isRecordingVideo = false
                }
            }
        }
        
        videoRecorder?.onRecordingComplete = { [weak self] url in
            DispatchQueue.main.async {
                self?.hideRecordingIndicator()
                self?.isRecordingVideo = false
                self?.handleVideoComplete(url: url)
            }
        }
        
        videoRecorder?.onRecordingError = { [weak self] error in
            DispatchQueue.main.async {
                self?.hideRecordingIndicator()
                self?.isRecordingVideo = false
                print("Recording error: \(error)")
            }
        }
    }
    
    func stopVideoRecording() {
        guard isRecordingVideo else { return }
        
        Task {
            await videoRecorder?.stopRecording()
        }
    }
    
    private func showRecordingIndicator(for rect: CGRect) {
        recordingIndicator = RecordingIndicatorWindow(captureRect: rect)
        recordingIndicator?.onStop = { [weak self] in
            self?.stopVideoRecording()
        }
        recordingIndicator?.makeKeyAndOrderFront(nil)
    }
    
    private func hideRecordingIndicator() {
        recordingIndicator?.close()
        recordingIndicator = nil
    }
    
    private func handleVideoComplete(url: URL) {
        // For now, show the video file location
        // TODO: Add video preview and upload
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
        
        // Copy path to clipboard for now
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
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
                    HistoryManager.shared.add(url: url, filename: filename)
                    
                    self?.delegate?.captureManagerDidUpload(url: url)
                    self?.previewWindow?.showSuccess(url: url)
                    
                case .failure(let error):
                    self?.previewWindow?.showError(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Recording Indicator Window

class RecordingIndicatorWindow: NSWindow {
    var onStop: (() -> Void)?
    private var pulseTimer: Timer?
    private var recordingDot: NSView!
    
    init(captureRect: CGRect) {
        let windowRect = NSRect(x: captureRect.midX - 60, y: captureRect.maxY + 20, width: 120, height: 36)
        
        super.init(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        
        setupViews()
        startPulsing()
    }
    
    private func setupViews() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        container.layer?.cornerRadius = 18
        
        // Recording dot
        recordingDot = NSView(frame: NSRect(x: 12, y: 12, width: 12, height: 12))
        recordingDot.wantsLayer = true
        recordingDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        recordingDot.layer?.cornerRadius = 6
        container.addSubview(recordingDot)
        
        // Stop button
        let stopButton = NSButton(frame: NSRect(x: 32, y: 6, width: 80, height: 24))
        stopButton.title = "Stop"
        stopButton.bezelStyle = .rounded
        stopButton.target = self
        stopButton.action = #selector(stopClicked)
        container.addSubview(stopButton)
        
        self.contentView = container
    }
    
    private func startPulsing() {
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            let currentAlpha = self?.recordingDot.layer?.opacity ?? 1
            self?.recordingDot.layer?.opacity = currentAlpha > 0.5 ? 0.3 : 1.0
        }
    }
    
    @objc private func stopClicked() {
        onStop?()
    }
    
    override func close() {
        pulseTimer?.invalidate()
        super.close()
    }
}
