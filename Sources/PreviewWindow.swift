import AppKit

class PreviewWindow: NSWindow {
    var onClose: (() -> Void)?
    private var image: NSImage
    private var statusLabel: NSTextField!
    private var successLabel: NSTextField!
    private var imageView: DraggableImageView!
    private var statusBar: NSVisualEffectView!
    private var prevButton: NSButton!
    private var nextButton: NSButton!
    private var historyCountLabel: NSTextField!
    private var containerView: NSView!
    private var spinner: NSProgressIndicator!

    // History navigation
    private var historyItems: [HistoryItem] = []
    private var currentHistoryIndex: Int = -1  // -1 means showing current capture, not history
    private var currentURL: String?

    // Remember position within app session (resets on restart)
    private static var rememberedOrigin: NSPoint?

    init(image: NSImage, screen: NSScreen? = nil, url: String? = nil) {
        self.image = image
        self.currentURL = url

        let maxSize: CGFloat = 600
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
        let windowSize = NSSize(
            width: max(image.size.width * scale, 200),
            height: max(image.size.height * scale, 150) + 48
        )

        let targetScreen = screen ?? NSScreen.main
        let screenFrame = targetScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        // Use remembered position or center on screen
        let windowOrigin: NSPoint
        if let remembered = PreviewWindow.rememberedOrigin {
            windowOrigin = remembered
        } else {
            windowOrigin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.midY - windowSize.height / 2
            )
        }

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
        loadHistory()

        // Fade in animation
        self.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    private func loadHistory() {
        historyItems = HistoryManager.shared.getRecent(20)
        updateNavigationState()
    }

    private func updateNavigationState() {
        let hasHistory = !historyItems.isEmpty
        let canGoPrev = currentHistoryIndex < historyItems.count - 1
        let canGoNext = currentHistoryIndex > -1

        prevButton.isEnabled = hasHistory && canGoPrev
        nextButton.isEnabled = canGoNext
        prevButton.alphaValue = prevButton.isEnabled ? 1.0 : 0.3
        nextButton.alphaValue = nextButton.isEnabled ? 1.0 : 0.3

        // Update counter
        if currentHistoryIndex == -1 {
            historyCountLabel.stringValue = "New"
        } else {
            historyCountLabel.stringValue = "\(currentHistoryIndex + 1)/\(historyItems.count)"
        }
    }

    @objc private func navigatePrev() {
        guard currentHistoryIndex < historyItems.count - 1 else { return }
        currentHistoryIndex += 1
        loadHistoryItem(at: currentHistoryIndex)
    }

    @objc private func navigateNext() {
        guard currentHistoryIndex > -1 else { return }
        currentHistoryIndex -= 1
        if currentHistoryIndex == -1 {
            // Back to current capture
            imageView.image = image
            currentURL = nil
            updateNavigationState()
            successLabel.alphaValue = 0
            statusLabel.stringValue = "Drag to save · Press ESC to close"
        } else {
            loadHistoryItem(at: currentHistoryIndex)
        }
    }

    private func loadHistoryItem(at index: Int) {
        guard index >= 0 && index < historyItems.count else { return }
        let item = historyItems[index]
        currentURL = item.url

        // Show spinner
        spinner.isHidden = false
        spinner.startAnimation(nil)
        imageView.alphaValue = 0.3

        // Fetch image from URL
        guard let url = URL(string: item.url) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.spinner.stopAnimation(nil)
                self.spinner.isHidden = true
                self.imageView.alphaValue = 1

                if let data = data, let loadedImage = NSImage(data: data) {
                    self.imageView.image = loadedImage
                    self.statusLabel.stringValue = "← → navigate · Drag to save · ESC to close"
                } else {
                    self.successLabel.stringValue = "Failed to load"
                    self.successLabel.textColor = .systemRed
                    self.successLabel.alphaValue = 1
                }
                self.updateNavigationState()
            }
        }.resume()
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    private func setupViews(windowSize: NSSize) {
        containerView = NSView(frame: NSRect(origin: .zero, size: windowSize))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        containerView.layer?.cornerRadius = 12
        containerView.layer?.masksToBounds = true

        // Status bar with vibrancy
        let statusBarHeight: CGFloat = 48
        statusBar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: windowSize.width, height: statusBarHeight))
        statusBar.material = .headerView
        statusBar.blendingMode = .withinWindow
        statusBar.state = .active
        containerView.addSubview(statusBar)

        // Subtle separator line
        let separator = NSView(frame: NSRect(x: 0, y: statusBarHeight - 0.5, width: windowSize.width, height: 0.5))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        containerView.addSubview(separator)

        // Navigation buttons
        let buttonSize: CGFloat = 28
        let buttonY: CGFloat = (statusBarHeight - buttonSize) / 2

        prevButton = NSButton(frame: NSRect(x: 8, y: buttonY, width: buttonSize, height: buttonSize))
        prevButton.bezelStyle = .regularSquare
        prevButton.isBordered = false
        prevButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous")
        prevButton.contentTintColor = .secondaryLabelColor
        prevButton.target = self
        prevButton.action = #selector(navigatePrev)
        statusBar.addSubview(prevButton)

        nextButton = NSButton(frame: NSRect(x: windowSize.width - buttonSize - 8, y: buttonY, width: buttonSize, height: buttonSize))
        nextButton.bezelStyle = .regularSquare
        nextButton.isBordered = false
        nextButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")
        nextButton.contentTintColor = .secondaryLabelColor
        nextButton.target = self
        nextButton.action = #selector(navigateNext)
        statusBar.addSubview(nextButton)

        // History count label (between buttons, top)
        historyCountLabel = NSTextField(frame: NSRect(x: buttonSize + 12, y: 26, width: windowSize.width - (buttonSize + 12) * 2, height: 16))
        historyCountLabel.isEditable = false
        historyCountLabel.isBordered = false
        historyCountLabel.backgroundColor = .clear
        historyCountLabel.textColor = .tertiaryLabelColor
        historyCountLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        historyCountLabel.alignment = .center
        historyCountLabel.stringValue = ""
        statusBar.addSubview(historyCountLabel)

        // Success indicator (hidden initially)
        successLabel = NSTextField(frame: NSRect(x: buttonSize + 12, y: 26, width: windowSize.width - (buttonSize + 12) * 2, height: 18))
        successLabel.isEditable = false
        successLabel.isBordered = false
        successLabel.backgroundColor = .clear
        successLabel.textColor = NSColor(red: 0.18, green: 0.55, blue: 0.34, alpha: 1.0)
        successLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        successLabel.alignment = .center
        successLabel.stringValue = ""
        successLabel.alphaValue = 0
        statusBar.addSubview(successLabel)

        // Hint label
        statusLabel = NSTextField(frame: NSRect(x: buttonSize + 12, y: 8, width: windowSize.width - (buttonSize + 12) * 2, height: 16))
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.alignment = .center
        statusLabel.stringValue = "Drag to save · Press ESC to close"
        statusBar.addSubview(statusLabel)

        // Image view
        let imageHeight = windowSize.height - statusBarHeight
        imageView = DraggableImageView(frame: NSRect(x: 8, y: statusBarHeight + 4, width: windowSize.width - 16, height: imageHeight - 12))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        containerView.addSubview(imageView)

        // Spinner for loading states
        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.sizeToFit()
        spinner.frame.origin = NSPoint(
            x: imageView.frame.midX - spinner.frame.width / 2,
            y: imageView.frame.midY - spinner.frame.height / 2
        )
        spinner.isHidden = true
        containerView.addSubview(spinner)

        self.contentView = containerView
    }
    
    override func close() {
        // Remember position before closing
        PreviewWindow.rememberedOrigin = self.frame.origin
        
        let closeCallback = onClose
        onClose = nil
        orderOut(nil)
        closeCallback?()
    }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // ESC
            close()
        case 123: // Left arrow
            navigatePrev()
        case 124: // Right arrow
            navigateNext()
        default:
            super.keyDown(with: event)
        }
    }
    
    func showSuccess(url: String) {
        currentURL = url
        successLabel.stringValue = "✓ Copied to clipboard"
        successLabel.textColor = NSColor(red: 0.18, green: 0.55, blue: 0.34, alpha: 1.0)

        // Animate success label in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            successLabel.animator().alphaValue = 1
        }

        // Fade out after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self?.successLabel.animator().alphaValue = 0
            }
        }
    }

    func showError(_ message: String) {
        successLabel.stringValue = "✗ \(message)"
        successLabel.textColor = .systemRed
        successLabel.alphaValue = 1
    }

    func showUploading() {
        successLabel.stringValue = "Uploading..."
        successLabel.textColor = .secondaryLabelColor
        successLabel.alphaValue = 1
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
