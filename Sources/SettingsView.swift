import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var endpoint: String = ""
    @State private var bucket: String = ""
    @State private var region: String = ""
    @State private var accessKey: String = ""
    @State private var secretKey: String = ""
    @State private var publicURLBase: String = ""
    @State private var showSaveConfirmation = false
    @State private var launchAtLogin: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("🍐")
                    .font(.system(size: 40))
                Text("Pearsnap")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Screenshot & Upload")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // General section
                    SettingsSection(title: "General", icon: "gearshape") {
                        Toggle("Launch at Login", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { newValue in
                                setLaunchAtLogin(newValue)
                            }
                    }
                    
                    // S3 Configuration section
                    SettingsSection(title: "Storage", icon: "cloud") {
                        VStack(spacing: 12) {
                            SettingsTextField(label: "Endpoint", text: $endpoint, placeholder: "nyc3.digitaloceanspaces.com")
                            SettingsTextField(label: "Bucket", text: $bucket, placeholder: "my-bucket")
                            SettingsTextField(label: "Region", text: $region, placeholder: "nyc3")
                        }
                    }
                    
                    // Credentials section
                    SettingsSection(title: "Credentials", icon: "key") {
                        VStack(spacing: 12) {
                            SettingsTextField(label: "Access Key", text: $accessKey, placeholder: "Your access key")
                            SettingsSecureField(label: "Secret Key", text: $secretKey, placeholder: "Your secret key")
                        }
                    }
                    
                    // Public URL section
                    SettingsSection(title: "Public URL", icon: "link") {
                        SettingsTextField(label: "URL Base", text: $publicURLBase, placeholder: "https://bucket.nyc3.cdn.digitaloceanspaces.com")
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer with save button
            HStack {
                if showSaveConfirmation {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
                Spacer()
                Button(action: saveConfig) {
                    Text("Save Settings")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(16)
        }
        .frame(width: 420, height: 520)
        .onAppear {
            loadConfig()
            loadLaunchAtLogin()
        }
    }
    
    private func loadConfig() {
        if let config = ConfigManager.shared.config {
            endpoint = config.s3Endpoint
            bucket = config.s3Bucket
            region = config.s3Region
            accessKey = config.s3AccessKey
            secretKey = config.s3SecretKey
            publicURLBase = config.publicURLBase
        } else {
            let empty = S3Config.empty
            endpoint = empty.s3Endpoint
            region = empty.s3Region
        }
    }
    
    private func loadLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLogin = false
        }
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to set launch at login: \(error)")
            }
        }
    }
    
    private func saveConfig() {
        ConfigManager.shared.config = S3Config(
            s3Endpoint: endpoint,
            s3Bucket: bucket,
            s3Region: region,
            s3AccessKey: accessKey,
            s3SecretKey: secretKey,
            publicURLBase: publicURLBase
        )
        
        showSaveConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSaveConfirmation = false
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.primary)
            
            content
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)
        }
    }
}

struct SettingsTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct SettingsSecureField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            SecureField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
