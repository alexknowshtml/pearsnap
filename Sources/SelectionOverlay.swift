import AppKit

protocol SelectionOverlayDelegate: AnyObject {
    func selectionOverlay(_ overlay: SelectionOverlay, didSelectRegion rect: CGRect, screen: NSScreen)
    func selectionOverlayCancelled(_ overlay: SelectionOverlay)
}

class SelectionOverlay: NSWindow {
    weak var selectionDelegate: SelectionOverlayDelegate?
    
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var selectionRect: CGRect?
    private var modeLabel: NSTextField!
    private var trackingArea: NSTrackingArea?
    var overlayScreen: NSScreen?
    private var loupeView: LoupeView!
    private var screenSnapshot: CGImage?
    private var currentHexColor: String = "#FFFFFF"
    
    init(screen: NSScreen) {
        self.overlayScreen = screen
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Capture screen BEFORE showing overlay
        captureScreenSnapshot()
        
        self.level = .screenSaver
        self.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.isReleasedWhenClosed = false
        
        let contentView = SelectionContentView(frame: screen.frame)
        contentView.overlay = self
        self.contentView = contentView
        
        setupLabels()
        setupLoupe()
        setupTracking()
        
        NSCursor.crosshair.push()
        
        // Make window key immediately to receive events
        makeKeyAndOrderFront(nil)
    }
    
    private func captureScreenSnapshot() {
        guard let screen = overlayScreen else { return }
        
        let screenRect = CGRect(
            x: screen.frame.origin.x,
            y: NSScreen.screens[0].frame.height - screen.frame.origin.y - screen.frame.height,
            width: screen.frame.width,
            height: screen.frame.height
        )
        
        screenSnapshot = CGWindowListCreateImage(
            screenRect,
            .optionOnScreenBelowWindow,
            kCGNullWindowID,
            .bestResolution
        )
    }
    
    private func setupLabels() {
        modeLabel = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        modeLabel.isEditable = false
        modeLabel.isBordered = false
        modeLabel.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        modeLabel.textColor = .white
        modeLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        modeLabel.alignment = .center
        modeLabel.stringValue = "📷 Screenshot · ⌘C=copy color"
        modeLabel.wantsLayer = true
        modeLabel.layer?.cornerRadius = 6
        
        modeLabel.frame.origin = NSPoint(
            x: frame.width / 2 - 120,
            y: frame.height - 60
        )
        contentView?.addSubview(modeLabel)
    }
    
    private func setupLoupe() {
        loupeView = LoupeView(frame: NSRect(x: 0, y: 0, width: 140, height: 170))
        loupeView.isHidden = true
        contentView?.addSubview(loupeView)
    }
    
    private func setupTracking() {
        if let contentView = contentView {
            let trackingArea = NSTrackingArea(
                rect: contentView.bounds,
                options: [.mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            contentView.addTrackingArea(trackingArea)
            self.trackingArea = trackingArea
        }
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        switch event.keyCode {
        case 53: // ESC
            close()
            selectionDelegate?.selectionOverlayCancelled(self)
        case 8: // C key
            if flags == .command {
                copyColorToClipboard()
            }
        default:
            super.keyDown(with: event)
        }
    }
    
    private func copyColorToClipboard() {
        // Use our stored hex value
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentHexColor, forType: .string)
        
        // Close overlay after copy
        NSCursor.pop()
        close()
        selectionDelegate?.selectionOverlayCancelled(self)
    }
    
    override func mouseMoved(with event: NSEvent) {
        let point = event.locationInWindow
        updateLoupe(at: point)
        
        if let contentView = contentView as? SelectionContentView {
            contentView.mouseLocation = point
            contentView.needsDisplay = true
        }
    }
    
    private func updateLoupe(at windowPoint: NSPoint) {
        guard let snapshot = screenSnapshot, let screen = overlayScreen else {
            loupeView.isHidden = true
            return
        }
        
        let screenPoint = NSPoint(
            x: windowPoint.x,
            y: windowPoint.y
        )
        
        let snapshotScale = CGFloat(snapshot.width) / screen.frame.width
        let snapshotX = Int(screenPoint.x * snapshotScale)
        let snapshotY = Int((screen.frame.height - screenPoint.y) * snapshotScale)
        
        if let color = getColorFromSnapshot(x: snapshotX, y: snapshotY) {
            let rgb = color.usingColorSpace(.deviceRGB) ?? color
            currentHexColor = String(format: "#%02X%02X%02X",
                            Int(rgb.redComponent * 255),
                            Int(rgb.greenComponent * 255),
                            Int(rgb.blueComponent * 255))
            loupeView.updateColor(color, hex: currentHexColor)
        }
        
        loupeView.updateSnapshot(snapshot, centerX: snapshotX, centerY: snapshotY, scale: snapshotScale)
        
        var loupeX = windowPoint.x + 30
        var loupeY = windowPoint.y + 30
        
        if loupeX + loupeView.frame.width > frame.width {
            loupeX = windowPoint.x - loupeView.frame.width - 30
        }
        if loupeY + loupeView.frame.height > frame.height {
            loupeY = windowPoint.y - loupeView.frame.height - 30
        }
        
        loupeView.frame.origin = NSPoint(x: loupeX, y: loupeY)
        loupeView.isHidden = false
    }
    
    private func getColorFromSnapshot(x: Int, y: Int) -> NSColor? {
        guard let snapshot = screenSnapshot else { return nil }
        
        let width = snapshot.width
        let height = snapshot.height
        
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        
        guard let dataProvider = snapshot.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        
        let bytesPerPixel = snapshot.bitsPerPixel / 8
        let bytesPerRow = snapshot.bytesPerRow
        let offset = y * bytesPerRow + x * bytesPerPixel
        
        let b = CGFloat(ptr[offset]) / 255.0
        let g = CGFloat(ptr[offset + 1]) / 255.0
        let r = CGFloat(ptr[offset + 2]) / 255.0
        
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        currentPoint = startPoint
        loupeView.isHidden = true
        
        updateSelectionRect()
        if let contentView = contentView as? SelectionContentView {
            contentView.needsDisplay = true
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        currentPoint = event.locationInWindow
        updateSelectionRect()
        
        if let contentView = contentView as? SelectionContentView {
            contentView.needsDisplay = true
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        guard let rect = selectionRect, rect.width > 10, rect.height > 10 else {
            startPoint = nil
            currentPoint = nil
            selectionRect = nil
            loupeView.isHidden = false
            
            if let contentView = contentView as? SelectionContentView {
                contentView.selectionRect = nil
                contentView.needsDisplay = true
            }
            return
        }
        
        let screenRect = CGRect(
            x: frame.origin.x + rect.origin.x,
            y: frame.origin.y + rect.origin.y,
            width: rect.width,
            height: rect.height
        )
        
        NSCursor.pop()
        close()
        
        selectionDelegate?.selectionOverlay(self, didSelectRegion: screenRect, screen: overlayScreen ?? NSScreen.main!)
    }
    
    private func updateSelectionRect() {
        guard let start = startPoint, let current = currentPoint else { return }
        
        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)
        
        selectionRect = CGRect(x: x, y: y, width: width, height: height)
        
        if let contentView = contentView as? SelectionContentView {
            contentView.selectionRect = selectionRect
        }
    }
    
    override func close() {
        NSCursor.pop()
        super.close()
    }
}

// MARK: - Loupe View

class LoupeView: NSView {
    private var zoomedImage: NSImage?
    private var hexLabel: NSTextField!
    private var colorSwatch: NSView!
    private var currentColor: NSColor = .white
    private let gridSize = 11
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.9).cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        
        colorSwatch = NSView(frame: NSRect(x: 10, y: 130, width: 30, height: 30))
        colorSwatch.wantsLayer = true
        colorSwatch.layer?.cornerRadius = 4
        colorSwatch.layer?.borderWidth = 1
        colorSwatch.layer?.borderColor = NSColor.white.cgColor
        addSubview(colorSwatch)
        
        hexLabel = NSTextField(frame: NSRect(x: 45, y: 133, width: 85, height: 24))
        hexLabel.isEditable = false
        hexLabel.isBordered = false
        hexLabel.backgroundColor = .clear
        hexLabel.textColor = .white
        hexLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        hexLabel.alignment = .left
        hexLabel.stringValue = "#FFFFFF"
        addSubview(hexLabel)
    }
    
    func updateColor(_ color: NSColor, hex: String) {
        currentColor = color
        hexLabel.stringValue = hex
        colorSwatch.layer?.backgroundColor = color.cgColor
    }
    
    func updateSnapshot(_ snapshot: CGImage, centerX: Int, centerY: Int, scale: CGFloat) {
        let halfGrid = gridSize / 2
        let sourceRect = CGRect(
            x: max(0, centerX - halfGrid),
            y: max(0, centerY - halfGrid),
            width: gridSize,
            height: gridSize
        )
        
        if let croppedImage = snapshot.cropping(to: sourceRect) {
            zoomedImage = NSImage(cgImage: croppedImage, size: NSSize(width: gridSize, height: gridSize))
        }
        
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let loupeRect = NSRect(x: 10, y: 10, width: 120, height: 120)
        
        if let image = zoomedImage {
            NSGraphicsContext.current?.imageInterpolation = .none
            image.draw(in: loupeRect)
        }
        
        NSColor.black.withAlphaComponent(0.3).setStroke()
        let cellSize = loupeRect.width / CGFloat(gridSize)
        
        for i in 0...gridSize {
            let x = loupeRect.origin.x + CGFloat(i) * cellSize
            let y = loupeRect.origin.y + CGFloat(i) * cellSize
            
            let vPath = NSBezierPath()
            vPath.move(to: NSPoint(x: x, y: loupeRect.origin.y))
            vPath.line(to: NSPoint(x: x, y: loupeRect.maxY))
            vPath.lineWidth = 0.5
            vPath.stroke()
            
            let hPath = NSBezierPath()
            hPath.move(to: NSPoint(x: loupeRect.origin.x, y: y))
            hPath.line(to: NSPoint(x: loupeRect.maxX, y: y))
            hPath.lineWidth = 0.5
            hPath.stroke()
        }
        
        let centerCell = CGFloat(gridSize / 2)
        let centerRect = NSRect(
            x: loupeRect.origin.x + centerCell * cellSize,
            y: loupeRect.origin.y + centerCell * cellSize,
            width: cellSize,
            height: cellSize
        )
        
        NSColor.white.setStroke()
        let centerPath = NSBezierPath(rect: centerRect)
        centerPath.lineWidth = 2
        centerPath.stroke()
    }
}

// MARK: - Selection Content View

class SelectionContentView: NSView {
    weak var overlay: SelectionOverlay?
    var selectionRect: CGRect?
    var mouseLocation: NSPoint?
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        if let rect = selectionRect {
            NSColor.clear.setFill()
            let clearPath = NSBezierPath(rect: rect)
            clearPath.fill()
            
            NSColor.white.setStroke()
            let borderPath = NSBezierPath(rect: rect)
            borderPath.lineWidth = 2
            borderPath.stroke()
            
            let handleSize: CGFloat = 8
            NSColor.white.setFill()
            
            let corners = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY)
            ]
            
            for corner in corners {
                let handleRect = CGRect(
                    x: corner.x - handleSize/2,
                    y: corner.y - handleSize/2,
                    width: handleSize,
                    height: handleSize
                )
                NSBezierPath(ovalIn: handleRect).fill()
            }
            
            let sizeText = "\(Int(rect.width)) × \(Int(rect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            
            let textSize = sizeText.size(withAttributes: attrs)
            let textBgRect = NSRect(
                x: rect.midX - textSize.width/2 - 6,
                y: rect.maxY + 6,
                width: textSize.width + 12,
                height: textSize.height + 4
            )
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: textBgRect, xRadius: 4, yRadius: 4).fill()
            
            let textPoint = NSPoint(
                x: rect.midX - textSize.width/2,
                y: rect.maxY + 8
            )
            sizeText.draw(at: textPoint, withAttributes: attrs)
        }
        
        if selectionRect == nil, let mouseLocation = mouseLocation {
            NSColor.white.withAlphaComponent(0.6).setStroke()
            
            let hPath = NSBezierPath()
            hPath.move(to: NSPoint(x: 0, y: mouseLocation.y))
            hPath.line(to: NSPoint(x: bounds.width, y: mouseLocation.y))
            hPath.lineWidth = 1
            hPath.setLineDash([5, 5], count: 2, phase: 0)
            hPath.stroke()
            
            let vPath = NSBezierPath()
            vPath.move(to: NSPoint(x: mouseLocation.x, y: 0))
            vPath.line(to: NSPoint(x: mouseLocation.x, y: bounds.height))
            vPath.lineWidth = 1
            vPath.setLineDash([5, 5], count: 2, phase: 0)
            vPath.stroke()
            
            NSColor.white.setStroke()
            let centerPath = NSBezierPath()
            centerPath.move(to: NSPoint(x: mouseLocation.x - 10, y: mouseLocation.y))
            centerPath.line(to: NSPoint(x: mouseLocation.x + 10, y: mouseLocation.y))
            centerPath.move(to: NSPoint(x: mouseLocation.x, y: mouseLocation.y - 10))
            centerPath.line(to: NSPoint(x: mouseLocation.x, y: mouseLocation.y + 10))
            centerPath.lineWidth = 2
            centerPath.stroke()
        }
    }
}
