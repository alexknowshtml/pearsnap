import Foundation

struct S3Config: Codable {
    var s3Endpoint: String
    var s3Bucket: String
    var s3Region: String
    var s3AccessKey: String
    var s3SecretKey: String
    var publicURLBase: String
    
    static var empty: S3Config {
        S3Config(
            s3Endpoint: "nyc3.digitaloceanspaces.com",
            s3Bucket: "",
            s3Region: "nyc3",
            s3AccessKey: "",
            s3SecretKey: "",
            publicURLBase: ""
        )
    }
}

class ConfigManager {
    static let shared = ConfigManager()
    
    private let configURL: URL
    
    var config: S3Config? {
        didSet {
            if let config = config {
                save(config)
            }
        }
    }
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Pearsnap", isDirectory: true)
        
        // Create app folder if needed
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        configURL = appFolder.appendingPathComponent("config.json")
        config = load()
    }
    
    private func load() -> S3Config? {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(S3Config.self, from: data)
        } catch {
            print("Failed to load config: \(error)")
            return nil
        }
    }
    
    private func save(_ config: S3Config) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            let data = try encoder.encode(config)
            try data.write(to: configURL)
        } catch {
            print("Failed to save config: \(error)")
        }
    }
    
    var isConfigured: Bool {
        guard let config = config else { return false }
        return !config.s3Bucket.isEmpty && !config.s3AccessKey.isEmpty && !config.s3SecretKey.isEmpty
    }
}
