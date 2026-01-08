import AppKit
import ScreenCaptureKit

class PermissionsManager {
    static let shared = PermissionsManager()
    
    private init() {}
    
    // Check if accessibility is enabled (for global hotkey)
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }
    
    // Check if screen recording is enabled
    var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }
    
    // Request screen recording permission (shows system prompt)
    func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }
    
    // Open accessibility settings
    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    
    // Open screen recording settings
    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    
    // Check if all permissions are granted
    var allPermissionsGranted: Bool {
        hasAccessibilityPermission && hasScreenRecordingPermission
    }
    
    // Check if this is first launch (no config exists)
    var isFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    }
    
    func markAsLaunched() {
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    }
}
