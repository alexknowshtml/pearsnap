import AppKit

class PreviewWindow: NSWindow {
    var onClose: (() -> Void)?
    private var image: NSImage
    private var statusLabel: NSTextField!
    private var imageView: DraggableImageView!
    
    init(image: NSImage, screen: NSScreen? = nil) {
        self.image = image
        
        let maxSize: CGFloat = 600
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
        let windowSize = NSSize(
            width: max(image.size.width * scale, 200),
            height: max(image.size.height * scale, 150) + 40
        )
        
        let targetScreen = screen ?? NSScreen.main
        let screenFrame = targetScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        
        let windowOrigin = NSPoint(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2
        )
        
        super.init(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isMovableByWindowBackground = true
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isReleasedWhenClosed = false
        
        setupViews(windowSize: windowSize)
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    private func setupViews(windowSize: NSSize) {
        let containerView = NSView(frame: NSRect(origin: .zero, size: windowSize))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        containerView.layer?.cornerRadius = 10
        containerView.layer?.masksToBounds = true
        
        let imageHeight = windowSize.height - 40
        imageView = DraggableImageView(frame: NSRect(x: 8, y: 40, width: windowSize.width - 16, height: imageHeight - 8))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        containerView.addSubview(imageView)
        
        statusLabel = NSTextField(frame: NSRect(x: 10, y: 12, width: windowSize.width - 20, height: 20))
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.alignment = .center
        statusLabel.stringValue = "Drag to save · ESC to close"
        containerView.addSubview(statusLabel)
        
        self.contentView = containerView
    }
    
    override func close() {
        let closeCallback = onClose
        onClose = nil
        orderOut(nil)
        closeCallback?()
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
        } else {
            super.keyDown(with: event)
        }
    }
    
    func showSuccess(url: String) {
        statusLabel.stringValue = "Copied to clipboard · Drag to save · ESC to close"
        statusLabel.textColor = .systemGreen
    }
    
    func showError(_ message: String) {
        statusLabel.stringValue = "Error: \(message)"
        statusLabel.textColor = .systemRed
    }
    
    func showUploading() {
        statusLabel.stringValue = "Uploading..."
        statusLabel.textColor = .secondaryLabelColor
    }
}

class DraggableImageView: NSImageView, NSDraggingSource {
    private var mouseDownPoint: NSPoint = .zero
    private var isDragging = false
    private var tempFileURL: URL?
    
    override init(frame: NSRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        cleanupTempFile()
    }
    
    private func cleanupTempFile() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        isDragging = false
    }
    
    override func mouseDragged(with event: NSEvent) {
        let currentPoint = event.locationInWindow
        let distance = hypot(currentPoint.x - mouseDownPoint.x, currentPoint.y - mouseDownPoint.y)
        
        if distance > 5 && !isDragging {
            isDragging = true
            startDragging(event: event)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }
    
    private func createTempFile() -> URL? {
        guard let image = self.image,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "Screenshot \(formatter.string(from: Date())).png"
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        
        do {
            try pngData.write(to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }
    
    private func startDragging(event: NSEvent) {
        guard let image = self.image else { return }
        
        cleanupTempFile()
        
        guard let fileURL = createTempFile() else { return }
        tempFileURL = fileURL
        
        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        draggingItem.setDraggingFrame(bounds, contents: image)
        
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
    
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
    
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.cleanupTempFile()
        }
    }
}
