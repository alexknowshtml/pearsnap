import SwiftUI
import AppKit
import Carbon.HIToolbox

@main
struct PearsnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, CaptureManagerDelegate {
    var statusItem: NSStatusItem?
    var captureManager: CaptureManager?
    var eventTap: CFMachPort?
    var settingsWindow: NSWindow?
    var onboardingController: OnboardingWindowController?
    var permissionCheckTimer: Timer?
    var historyPreviewWindow: PreviewWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        setupMenuBar()
        captureManager = CaptureManager()
        captureManager?.delegate = self
        
        if PermissionsManager.shared.isFirstLaunch || !PermissionsManager.shared.allPermissionsGranted {
            showOnboarding()
        } else {
            setupHotkeyIfAllowed()
        }
    }
    
    func showOnboarding() {
        onboardingController = OnboardingWindowController()
        onboardingController?.show { [weak self] in
            self?.setupHotkeyIfAllowed()
            self?.startPermissionMonitoring()
        }
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.title = "🍐"
        }
        
        updateMenu()
    }
    
    func updateMenu() {
        let menu = NSMenu()
        
        if PermissionsManager.shared.allPermissionsGranted {
            menu.addItem(NSMenuItem(title: "Capture Screenshot (⌘⇧5)", action: #selector(captureScreenshot), keyEquivalent: ""))
        } else {
            let permItem = NSMenuItem(title: "⚠️ Permissions Required", action: #selector(showPermissions), keyEquivalent: "")
            menu.addItem(permItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // History section
        let historyItems = HistoryManager.shared.getRecent(10)
        if !historyItems.isEmpty {
            let historyHeader = NSMenuItem(title: "Recent Uploads", action: nil, keyEquivalent: "")
            historyHeader.isEnabled = false
            menu.addItem(historyHeader)
            
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            
            for item in historyItems {
                let timeAgo = formatter.localizedString(for: item.timestamp, relativeTo: Date())
                let menuItem = NSMenuItem(title: "\(item.filename) (\(timeAgo))", action: #selector(showHistoryItem(_:)), keyEquivalent: "")
                menuItem.representedObject = item
                menuItem.toolTip = item.url
                menu.addItem(menuItem)
            }
            
            menu.addItem(NSMenuItem.separator())
        }
        
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Check Permissions...", action: #selector(showPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Pearsnap", action: #selector(quit), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    // MARK: - CaptureManagerDelegate
    
    func captureManagerDidUpload(url: String) {
        updateMenu()
    }
    
    func startPermissionMonitoring() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            let hasAccess = PermissionsManager.shared.hasAccessibilityPermission
            if hasAccess && self?.eventTap == nil {
                self?.setupHotkeyIfAllowed()
                self?.updateMenu()
            }
        }
    }
    
    func setupHotkeyIfAllowed() {
        guard PermissionsManager.shared.hasAccessibilityPermission else {
            print("Accessibility permission not granted, skipping hotkey setup")
            return
        }
        
        guard eventTap == nil else {
            print("Event tap already set up")
            return
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                return appDelegate.handleKeyEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap")
            return
        }
        
        print("Event tap created successfully")
        eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        updateMenu()
    }
    
    func handleKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            
            let commandShift: CGEventFlags = [.maskCommand, .maskShift]
            if keyCode == 23 && flags.contains(commandShift) {
                DispatchQueue.main.async {
                    self.captureScreenshot()
                }
                return nil
            }
        }
        return Unmanaged.passRetained(event)
    }
    
    @objc func captureScreenshot() {
        guard PermissionsManager.shared.hasScreenRecordingPermission else {
            showPermissions()
            return
        }
        captureManager?.startCapture()
    }
    
    @objc func showHistoryItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? HistoryItem else { return }
        
        // Copy URL to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url, forType: .string)
        
        // Close any existing history preview
        historyPreviewWindow?.orderOut(nil)
        historyPreviewWindow = nil
        
        // Download and show preview
        guard let url = URL(string: item.url) else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, let image = NSImage(data: data) else {
                DispatchQueue.main.async {
                    // Show notification that URL was copied even if image failed to load
                    let notification = NSUserNotification()
                    notification.title = "URL Copied"
                    notification.informativeText = item.url
                    NSUserNotificationCenter.default.deliver(notification)
                }
                return
            }
            
            DispatchQueue.main.async {
                let preview = PreviewWindow(image: image)
                preview.showSuccess(url: item.url)
                preview.onClose = { [weak self] in
                    self?.historyPreviewWindow = nil
                }
                preview.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                self?.historyPreviewWindow = preview
            }
        }.resume()
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 350),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "Pearsnap Settings"
            settingsWindow?.contentView = NSHostingView(rootView: settingsView)
            settingsWindow?.center()
            settingsWindow?.isReleasedWhenClosed = false
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func showPermissions() {
        onboardingController = OnboardingWindowController()
        onboardingController?.show { [weak self] in
            self?.setupHotkeyIfAllowed()
            self?.updateMenu()
        }
    }
    
    @objc func quit() {
        NSApp.terminate(nil)
    }
}
