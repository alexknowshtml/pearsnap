import Foundation

struct HistoryItem: Codable {
    let url: String
    let timestamp: Date
    let filename: String
}

class HistoryManager {
    static let shared = HistoryManager()
    
    private let maxItems = 20
    private var items: [HistoryItem] = []
    private let historyURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Pearsnap", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        historyURL = appFolder.appendingPathComponent("history.json")
        load()
    }
    
    private func load() {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return }
        do {
            let data = try Data(contentsOf: historyURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([HistoryItem].self, from: data)
        } catch {
            print("Failed to load history: \(error)")
            // Try to recover by starting fresh
            items = []
        }
    }
    
    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: historyURL)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
    
    func add(url: String, filename: String) {
        let item = HistoryItem(url: url, timestamp: Date(), filename: filename)
        items.insert(item, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        save()
    }
    
    func getRecent(_ count: Int = 10) -> [HistoryItem] {
        return Array(items.prefix(count))
    }
    
    func clear() {
        items = []
        save()
    }
}
