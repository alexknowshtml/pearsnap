import AppKit
import ScreenCaptureKit

class PermissionsManager {
    static let shared = PermissionsManager()
    
    private init() {}
    
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }
    
    var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }
    
    func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }
    
    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    
    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    
    var allPermissionsGranted: Bool {
        hasAccessibilityPermission && hasScreenRecordingPermission
    }
    
    var isFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    }
    
    func markAsLaunched() {
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    }
    
    func resetAccessibilityPermission() {
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", "Accessibility", "com.alexhillman.Pearsnap"]
        try? task.run()
        task.waitUntilExit()
    }
    
    func resetScreenRecordingPermission() {
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", "ScreenCapture", "com.alexhillman.Pearsnap"]
        try? task.run()
        task.waitUntilExit()
    }
    
    func resetAndRelaunch() {
        // Reset both permissions
        resetAccessibilityPermission()
        resetScreenRecordingPermission()
        
        // Relaunch the app
        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            // Quit current instance after new one launches
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        }
    }
}
