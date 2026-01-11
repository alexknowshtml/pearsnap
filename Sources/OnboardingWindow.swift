import SwiftUI
import AppKit

struct OnboardingView: View {
    @State private var accessibilityGranted = PermissionsManager.shared.hasAccessibilityPermission
    @State private var screenRecordingGranted = PermissionsManager.shared.hasScreenRecordingPermission
    @State private var timer: Timer?
    @State private var accessibilityAttempted = false
    @State private var screenRecordingAttempted = false
    @State private var showTroubleshooting = false
    @State private var attemptStartTime: Date?
    
    var onComplete: () -> Void
    
    private let troubleshootingDelay: TimeInterval = 8.0
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("🍐")
                    .font(.system(size: 56))
                
                Text("Welcome to Pearsnap")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Quick screenshot capture & upload")
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            
            Divider()
                .padding(.horizontal)
            
            // Permissions section
            VStack(alignment: .leading, spacing: 16) {
                Text("Required Permissions")
                    .font(.headline)
                
                // Accessibility permission
                PermissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    description: "For global keyboard shortcut (⌘⇧5)",
                    isGranted: accessibilityGranted,
                    onEnable: {
                        accessibilityAttempted = true
                        startTroubleshootingTimer()
                        PermissionsManager.shared.openAccessibilitySettings()
                    }
                )
                
                // Screen recording permission
                PermissionRow(
                    icon: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    description: "To capture screenshots",
                    isGranted: screenRecordingGranted,
                    onEnable: {
                        screenRecordingAttempted = true
                        startTroubleshootingTimer()
                        PermissionsManager.shared.requestScreenRecordingPermission()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            PermissionsManager.shared.openScreenRecordingSettings()
                        }
                    }
                )
                
                // Troubleshooting section
                if showTroubleshooting && (!accessibilityGranted || !screenRecordingGranted) {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider()
                        
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Having trouble?")
                                .fontWeight(.medium)
                        }
                        
                        Text("If Pearsnap appears in System Settings but the checkbox won't stay enabled, click below to clear stale entries and restart.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Button(action: {
                            PermissionsManager.shared.resetAndRelaunch()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Reset Permissions & Relaunch")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.regular)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Continue button
            VStack(spacing: 8) {
                if accessibilityGranted && screenRecordingGranted {
                    Button(action: {
                        PermissionsManager.shared.markAsLaunched()
                        onComplete()
                    }) {
                        Text("Get Started")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("Grant permissions above, then click Continue")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        PermissionsManager.shared.markAsLaunched()
                        onComplete()
                    }) {
                        Text("Continue Anyway")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .frame(width: 400, height: showTroubleshooting ? 560 : 460)
        .onAppear {
            startPolling()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            accessibilityGranted = PermissionsManager.shared.hasAccessibilityPermission
            screenRecordingGranted = PermissionsManager.shared.hasScreenRecordingPermission
            
            if let startTime = attemptStartTime,
               Date().timeIntervalSince(startTime) > troubleshootingDelay {
                if (accessibilityAttempted && !accessibilityGranted) ||
                   (screenRecordingAttempted && !screenRecordingGranted) {
                    withAnimation {
                        showTroubleshooting = true
                    }
                }
            }
        }
    }
    
    private func startTroubleshootingTimer() {
        if attemptStartTime == nil {
            attemptStartTime = Date()
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let onEnable: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
                .foregroundColor(isGranted ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else {
                Button("Enable") {
                    onEnable()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

class OnboardingWindowController {
    var window: NSWindow?
    
    func show(onComplete: @escaping () -> Void) {
        let onboardingView = OnboardingView(onComplete: { [weak self] in
            self?.window?.close()
            onComplete()
        })
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window?.title = "Pearsnap Setup"
        window?.contentView = NSHostingView(rootView: onboardingView)
        window?.center()
        window?.isReleasedWhenClosed = false
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
