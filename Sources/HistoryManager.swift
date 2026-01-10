import Foundation
import AppKit

struct HistoryItem: Codable {
    let url: String
    let timestamp: Date
    let filename: String
    var thumbnailPath: String?
}

class HistoryManager {
    static let shared = HistoryManager()

    private let maxItems = 20
    private var items: [HistoryItem] = []
    private let historyURL: URL
    private let thumbnailsFolder: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Pearsnap", isDirectory: true)
        thumbnailsFolder = appFolder.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsFolder, withIntermediateDirectories: true)
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
    
    func add(url: String, filename: String, image: NSImage? = nil) {
        var thumbnailPath: String? = nil

        // Save thumbnail if image provided
        if let image = image {
            let thumbFilename = UUID().uuidString + ".png"
            let thumbURL = thumbnailsFolder.appendingPathComponent(thumbFilename)
            if let thumbnail = createThumbnail(from: image, maxSize: 32) {
                if let tiffData = thumbnail.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: thumbURL)
                    thumbnailPath = thumbFilename
                }
            }
        }

        let item = HistoryItem(url: url, timestamp: Date(), filename: filename, thumbnailPath: thumbnailPath)
        items.insert(item, at: 0)

        // Clean up old thumbnails
        if items.count > maxItems {
            let removed = items.suffix(from: maxItems)
            for old in removed {
                if let path = old.thumbnailPath {
                    try? FileManager.default.removeItem(at: thumbnailsFolder.appendingPathComponent(path))
                }
            }
            items = Array(items.prefix(maxItems))
        }
        save()
    }

    private func createThumbnail(from image: NSImage, maxSize: CGFloat) -> NSImage? {
        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height, 1.0)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        thumbnail.unlockFocus()
        return thumbnail
    }

    func thumbnail(for item: HistoryItem) -> NSImage? {
        guard let path = item.thumbnailPath else { return nil }
        let url = thumbnailsFolder.appendingPathComponent(path)
        return NSImage(contentsOf: url)
    }
    
    func getRecent(_ count: Int = 10) -> [HistoryItem] {
        return Array(items.prefix(count))
    }
    
    func clear() {
        items = []
        save()
    }
}
