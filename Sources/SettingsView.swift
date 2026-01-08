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
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
            } header: {
                Text("General")
            }
            
            Section {
                TextField("Endpoint", text: $endpoint)
                    .textFieldStyle(.roundedBorder)
                    .help("e.g., nyc3.digitaloceanspaces.com")
                
                TextField("Bucket Name", text: $bucket)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Region", text: $region)
                    .textFieldStyle(.roundedBorder)
                    .help("e.g., nyc3")
            } header: {
                Text("S3 Configuration")
            }
            
            Section {
                TextField("Access Key", text: $accessKey)
                    .textFieldStyle(.roundedBorder)
                
                SecureField("Secret Key", text: $secretKey)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Credentials")
            }
            
            Section {
                TextField("Public URL Base", text: $publicURLBase)
                    .textFieldStyle(.roundedBorder)
                    .help("e.g., https://your-bucket.nyc3.cdn.digitaloceanspaces.com")
            } header: {
                Text("Public Access")
            }
            
            HStack {
                Spacer()
                if showSaveConfirmation {
                    Text("Saved!")
                        .foregroundColor(.green)
                }
                Button("Save") {
                    saveConfig()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 400)
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
            // For older macOS, check legacy method
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
