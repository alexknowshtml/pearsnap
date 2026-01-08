import SwiftUI
import AppKit

struct OnboardingView: View {
    @State private var accessibilityGranted = PermissionsManager.shared.hasAccessibilityPermission
    @State private var screenRecordingGranted = PermissionsManager.shared.hasScreenRecordingPermission
    @State private var timer: Timer?
    
    var onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                
                Text("Welcome to Pearsnap")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Quick screenshot capture & upload")
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            
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
                    action: {
                        PermissionsManager.shared.openAccessibilitySettings()
                    }
                )
                
                // Screen recording permission
                PermissionRow(
                    icon: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    description: "To capture screenshots",
                    isGranted: screenRecordingGranted,
                    action: {
                        PermissionsManager.shared.requestScreenRecordingPermission()
                        // Also open settings since the prompt might not appear
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            PermissionsManager.shared.openScreenRecordingSettings()
                        }
                    }
                )
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
            .padding(.bottom, 20)
        }
        .frame(width: 380, height: 420)
        .onAppear {
            startPolling()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startPolling() {
        // Poll for permission changes every second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            accessibilityGranted = PermissionsManager.shared.hasAccessibilityPermission
            screenRecordingGranted = PermissionsManager.shared.hasScreenRecordingPermission
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    
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
                    action()
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
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
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
