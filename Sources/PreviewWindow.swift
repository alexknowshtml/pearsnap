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
    private var blurButton: NSButton!
    private var historyCountLabel: NSTextField!
    private var containerView: NSView!
    private var spinner: NSProgressIndicator!
    private var historyItems: [HistoryItem] = []
    private var currentHistoryIndex: Int = -1
    private var currentURL: String?
    private static var rememberedOrigin: NSPoint?
    private var preDragFrame: NSRect?
    private var preDragAlpha: CGFloat = 1.0
    private var isBlurMode = false
    private var blurOverlay: BlurOverlayView?

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
        let windowOrigin: NSPoint
        if let remembered = PreviewWindow.rememberedOrigin {
            windowOrigin = remembered
        } else {
            windowOrigin = NSPoint(x: screenFrame.midX - windowSize.width / 2, y: screenFrame.midY - windowSize.height / 2)
        }
        super.init(contentRect: NSRect(origin: windowOrigin, size: windowSize), styleMask: [.borderless], backing: .buffered, defer: false)
        self.isMovableByWindowBackground = true
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isReleasedWhenClosed = false
        self.title = "Pearsnap Preview"
        setupViews(windowSize: windowSize)
        loadHistory()
        NSApp.setActivationPolicy(.regular)
        self.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    private func loadHistory() {
        historyItems = HistoryManager.shared.getRecent(20)
        updateNavigationState()
    }

    private func updateNavigationState() {
        let hasHistory = !historyItems.isEmpty
        prevButton.isEnabled = hasHistory && currentHistoryIndex < historyItems.count - 1
        nextButton.isEnabled = currentHistoryIndex > -1
        prevButton.alphaValue = prevButton.isEnabled ? 1.0 : 0.3
        nextButton.alphaValue = nextButton.isEnabled ? 1.0 : 0.3
        historyCountLabel.stringValue = currentHistoryIndex == -1 ? "New" : "\(currentHistoryIndex + 1)/\(historyItems.count)"
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
        spinner.isHidden = false
        spinner.startAnimation(nil)
        imageView.alphaValue = 0.3
        guard let url = URL(string: item.url) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
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

        let statusBarHeight: CGFloat = 48
        statusBar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: windowSize.width, height: statusBarHeight))
        statusBar.material = .headerView
        statusBar.blendingMode = .withinWindow
        statusBar.state = .active
        containerView.addSubview(statusBar)

        let separator = NSView(frame: NSRect(x: 0, y: statusBarHeight - 0.5, width: windowSize.width, height: 0.5))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        containerView.addSubview(separator)

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
        
        blurButton = NSButton(frame: NSRect(x: windowSize.width - buttonSize * 2 - 16, y: buttonY, width: buttonSize, height: buttonSize))
        blurButton.bezelStyle = .regularSquare
        blurButton.isBordered = false
        blurButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Redact")
        blurButton.contentTintColor = .secondaryLabelColor
        blurButton.target = self
        blurButton.action = #selector(toggleBlurMode)
        blurButton.toolTip = "Redact sensitive areas"
        statusBar.addSubview(blurButton)

        historyCountLabel = NSTextField(frame: NSRect(x: buttonSize + 12, y: 26, width: windowSize.width - (buttonSize + 12) * 2 - 40, height: 16))
        historyCountLabel.isEditable = false
        historyCountLabel.isBordered = false
        historyCountLabel.backgroundColor = .clear
        historyCountLabel.textColor = .tertiaryLabelColor
        historyCountLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        historyCountLabel.alignment = .center
        statusBar.addSubview(historyCountLabel)

        successLabel = NSTextField(frame: NSRect(x: buttonSize + 12, y: 26, width: windowSize.width - (buttonSize + 12) * 2 - 40, height: 18))
        successLabel.isEditable = false
        successLabel.isBordered = false
        successLabel.backgroundColor = .clear
        successLabel.textColor = NSColor(red: 0.18, green: 0.55, blue: 0.34, alpha: 1.0)
        successLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        successLabel.alignment = .center
        successLabel.alphaValue = 0
        statusBar.addSubview(successLabel)

        statusLabel = NSTextField(frame: NSRect(x: buttonSize + 12, y: 8, width: windowSize.width - (buttonSize + 12) * 2 - 40, height: 16))
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.alignment = .center
        statusLabel.stringValue = "Drag to save · Press ESC to close"
        statusBar.addSubview(statusLabel)

        let imageHeight = windowSize.height - statusBarHeight
        imageView = DraggableImageView(frame: NSRect(x: 8, y: statusBarHeight + 4, width: windowSize.width - 16, height: imageHeight - 12))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.parentWindow = self
        containerView.addSubview(imageView)

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.sizeToFit()
        spinner.frame.origin = NSPoint(x: imageView.frame.midX - spinner.frame.width / 2, y: imageView.frame.midY - spinner.frame.height / 2)
        spinner.isHidden = true
        containerView.addSubview(spinner)

        self.contentView = containerView
    }
    
    @objc private func toggleBlurMode() {
        isBlurMode.toggle()
        if isBlurMode { enterBlurMode() } else { exitBlurMode() }
    }
    
    private func enterBlurMode() {
        blurButton.contentTintColor = .systemRed
        statusLabel.stringValue = "Draw rectangles to redact · Click ✓ when done"
        imageView.isDragEnabled = false
        self.isMovableByWindowBackground = false
        let overlay = BlurOverlayView(frame: imageView.bounds)
        blurOverlay = overlay
        imageView.addSubview(overlay)
        blurButton.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Done")
        blurButton.toolTip = "Apply redaction"
    }
    
    private func exitBlurMode() {
        if let overlay = blurOverlay, !overlay.blurRects.isEmpty {
            applyRedaction(rects: overlay.blurRects)
        }
        blurButton.contentTintColor = .secondaryLabelColor
        blurButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Redact")
        blurButton.toolTip = "Redact sensitive areas"
        statusLabel.stringValue = "Drag to save · Press ESC to close"
        imageView.isDragEnabled = true
        self.isMovableByWindowBackground = true
        blurOverlay?.removeFromSuperview()
        blurOverlay = nil
    }
    
    private func applyRedaction(rects: [CGRect]) {
        guard let currentImage = imageView.image, !rects.isEmpty else { return }
        guard let cgImage = currentImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let viewSize = imageView.bounds.size
        
        // Calculate display rect (aspect fit)
        let imageAspect = imageWidth / imageHeight
        let viewAspect = viewSize.width / viewSize.height
        var displayRect: CGRect
        if imageAspect > viewAspect {
            let displayHeight = viewSize.width / imageAspect
            displayRect = CGRect(x: 0, y: (viewSize.height - displayHeight) / 2, width: viewSize.width, height: displayHeight)
        } else {
            let displayWidth = viewSize.height * imageAspect
            displayRect = CGRect(x: (viewSize.width - displayWidth) / 2, y: 0, width: displayWidth, height: viewSize.height)
        }
        
        // Create mutable copy of image
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: Int(imageWidth), height: Int(imageHeight),
            bitsPerComponent: 8, bytesPerRow: Int(imageWidth) * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        
        // Draw original image (CGContext is bottom-left, CGImage is top-left)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        
        // Get pixel data
        guard let pixelData = context.data else { return }
        let data = pixelData.bindMemory(to: UInt8.self, capacity: Int(imageWidth * imageHeight) * 4)
        
        for viewRect in rects {
            let scaleX = imageWidth / displayRect.width
            let scaleY = imageHeight / displayRect.height
            
            // View coords to image coords (flip Y because CGContext origin is bottom-left but image data is top-left)
            let imgX = (viewRect.origin.x - displayRect.origin.x) * scaleX
            let imgY = imageHeight - ((viewRect.origin.y - displayRect.origin.y + viewRect.height) * scaleY)
            let imgW = viewRect.width * scaleX
            let imgH = viewRect.height * scaleY
            
            let redactRect = CGRect(x: imgX, y: imgY, width: imgW, height: imgH)
                .intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            guard redactRect.width > 0, redactRect.height > 0 else { continue }
            
            // Big chunky blocks - about 8 blocks across
            let blockSize = Int(max(redactRect.width, redactRect.height) / 8)
            guard blockSize >= 2 else { continue }
            
            let startX = Int(redactRect.minX)
            let startY = Int(redactRect.minY)
            let endX = Int(redactRect.maxX)
            let endY = Int(redactRect.maxY)
            
            var by = startY
            while by < endY {
                var bx = startX
                while bx < endX {
                    // Sample center of block
                    let sampleX = min(bx + blockSize / 2, endX - 1)
                    let sampleY = min(by + blockSize / 2, endY - 1)
                    let sampleOffset = (sampleY * Int(imageWidth) + sampleX) * 4
                    
                    let r = data[sampleOffset]
                    let g = data[sampleOffset + 1]
                    let b = data[sampleOffset + 2]
                    
                    // Fill entire block with sampled color
                    let blockEndX = min(bx + blockSize, endX)
                    let blockEndY = min(by + blockSize, endY)
                    
                    for py in by..<blockEndY {
                        for px in bx..<blockEndX {
                            let offset = (py * Int(imageWidth) + px) * 4
                            data[offset] = r
                            data[offset + 1] = g
                            data[offset + 2] = b
                            data[offset + 3] = 255
                        }
                    }
                    bx += blockSize
                }
                by += blockSize
            }
        }
        
        guard let finalCG = context.makeImage() else { return }
        let finalImage = NSImage(cgImage: finalCG, size: NSSize(width: imageWidth, height: imageHeight))
        
        self.image = finalImage
        imageView.image = finalImage
        
        successLabel.stringValue = "✓ Redacted"
        successLabel.textColor = NSColor.systemRed
        successLabel.alphaValue = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.3; self?.successLabel.animator().alphaValue = 0 }
        }
    }
    
    override func close() {
        if isBlurMode { exitBlurMode() }
        PreviewWindow.rememberedOrigin = self.frame.origin
        NSApp.setActivationPolicy(.accessory)
        let closeCallback = onClose
        onClose = nil
        orderOut(nil)
        closeCallback?()
    }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: if isBlurMode { exitBlurMode() } else { close() }
        case 123: if !isBlurMode { navigatePrev() }
        case 124: if !isBlurMode { navigateNext() }
        default: super.keyDown(with: event)
        }
    }
    
    func animateOutForDrag() {
        guard preDragFrame == nil else { return }
        preDragFrame = frame
        preDragAlpha = alphaValue
        guard let screen = screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let windowCenter = NSPoint(x: frame.midX, y: frame.midY)
        let cornerSize: CGFloat = 80, margin: CGFloat = 20
        let corners = [
            NSPoint(x: screenFrame.minX + margin, y: screenFrame.minY + margin),
            NSPoint(x: screenFrame.maxX - cornerSize - margin, y: screenFrame.minY + margin),
            NSPoint(x: screenFrame.minX + margin, y: screenFrame.maxY - cornerSize - margin),
            NSPoint(x: screenFrame.maxX - cornerSize - margin, y: screenFrame.maxY - cornerSize - margin)
        ]
        let nearestCorner = corners.min { hypot($0.x - windowCenter.x, $0.y - windowCenter.y) < hypot($1.x - windowCenter.x, $1.y - windowCenter.y) }!
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            animator().setFrame(NSRect(origin: nearestCorner, size: NSSize(width: cornerSize, height: cornerSize)), display: true)
            animator().alphaValue = 0.4
        }
    }
    
    func animateBackFromDrag(completion: (() -> Void)? = nil) {
        guard let originalFrame = preDragFrame else { completion?(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            animator().setFrame(originalFrame, display: true)
            animator().alphaValue = preDragAlpha
        }, completionHandler: { self.preDragFrame = nil; completion?() })
    }
    
    func showSuccess(url: String) {
        currentURL = url
        successLabel.stringValue = "✓ Copied to clipboard"
        successLabel.textColor = NSColor(red: 0.18, green: 0.55, blue: 0.34, alpha: 1.0)
        successLabel.alphaValue = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.4; self?.successLabel.animator().alphaValue = 0 }
        }
    }
    func showError(_ message: String) { successLabel.stringValue = "✗ \(message)"; successLabel.textColor = .systemRed; successLabel.alphaValue = 1 }
    func showUploading() { successLabel.stringValue = "Uploading..."; successLabel.textColor = .secondaryLabelColor; successLabel.alphaValue = 1 }
}

class BlurOverlayView: NSView {
    var blurRects: [CGRect] = []
    private var currentRect: CGRect?
    private var startPoint: NSPoint?
    
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    
    override func mouseDown(with event: NSEvent) { startPoint = convert(event.locationInWindow, from: nil); currentRect = nil; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        currentRect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let rect = currentRect, rect.width > 5, rect.height > 5 { blurRects.append(rect) }
        currentRect = nil; startPoint = nil; needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.systemRed.withAlphaComponent(0.3).setFill()
        NSColor.systemRed.setStroke()
        for rect in blurRects { let p = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4); p.fill(); p.lineWidth = 2; p.stroke() }
        if let rect = currentRect {
            NSColor.systemRed.withAlphaComponent(0.2).setFill()
            let p = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4); p.fill()
            NSColor.systemRed.setStroke(); p.lineWidth = 2; p.setLineDash([5, 3], count: 2, phase: 0); p.stroke()
        }
    }
}

class DraggableImageView: NSImageView, NSDraggingSource {
    weak var parentWindow: PreviewWindow?
    var isDragEnabled = true
    private var mouseDownPoint: NSPoint = .zero, isDragging = false, tempFileURL: URL?
    
    override init(frame: NSRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let url = tempFileURL { try? FileManager.default.removeItem(at: url) } }
    
    override func mouseDown(with event: NSEvent) { guard isDragEnabled else { return }; mouseDownPoint = event.locationInWindow; isDragging = false }
    override func mouseDragged(with event: NSEvent) {
        guard isDragEnabled else { return }
        let cur = event.locationInWindow
        if hypot(cur.x - mouseDownPoint.x, cur.y - mouseDownPoint.y) > 5 && !isDragging { isDragging = true; startDragging(event: event) }
    }
    override func mouseUp(with event: NSEvent) { guard isDragEnabled else { return }; isDragging = false }
    
    private func startDragging(event: NSEvent) {
        guard let image = self.image else { return }
        if let url = tempFileURL { try? FileManager.default.removeItem(at: url); tempFileURL = nil }
        guard let tiffData = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Screenshot \(formatter.string(from: Date())).png")
        do { try pngData.write(to: url); tempFileURL = url } catch { return }
        parentWindow?.animateOutForDrag()
        let item = NSDraggingItem(pasteboardWriter: url as NSURL); item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        parentWindow?.animateBackFromDrag { if operation != [] { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.parentWindow?.close() } } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in if let u = self?.tempFileURL { try? FileManager.default.removeItem(at: u); self?.tempFileURL = nil } }
    }
}
