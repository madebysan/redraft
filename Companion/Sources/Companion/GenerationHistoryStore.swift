import Foundation

// Serialized background I/O; one file per result avoids rewriting the whole archive.
actor GenerationHistoryStore {
    static let shared = GenerationHistoryStore()
    static let visibleEntryLimit = 500

    struct Entry: Codable, Identifiable {
        let id: UUID
        let createdAt: Date
        let actionLabel: String
        let provider: String
        let model: String
        let selectedWordCount: Int
        let hadImages: Bool
        let imageFileNames: [String]
        let result: String
    }

    private let directory: URL
    private let legacyDirectory: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cache: [Entry]?

    init(directory: URL? = nil, legacyDirectory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let preview = Bundle.main.bundleIdentifier?.hasSuffix(".preview") == true
        self.directory = directory ?? base.appendingPathComponent(preview ? "CompanionPreview" : "Companion")
        self.legacyDirectory = legacyDirectory ?? (directory == nil && !preview ? base.appendingPathComponent("CompanionV2") : nil)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    private var entriesDirectory: URL { directory.appendingPathComponent("entries", isDirectory: true) }

    func entries() throws -> [Entry] {
        if let cache { return cache }
        var loaded: [Entry] = []
        let archive = directory.appendingPathComponent("history.json")
        let legacy = legacyDirectory?.appendingPathComponent("history.json")
        let source = FileManager.default.fileExists(atPath: archive.path) ? archive : legacy
        if let source, FileManager.default.fileExists(atPath: source.path) {
            loaded = try decoder.decode([Entry].self, from: Data(contentsOf: source))
        }
        if FileManager.default.fileExists(atPath: entriesDirectory.path) {
            let files = try FileManager.default.contentsOfDirectory(at: entriesDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
                .prefix(Self.visibleEntryLimit)
            for file in files { loaded.append(try decoder.decode(Entry.self, from: Data(contentsOf: file))) }
        }
        var seen = Set<UUID>()
        let visible = loaded.sorted { $0.createdAt > $1.createdAt }
            .filter { seen.insert($0.id).inserted }.prefix(Self.visibleEntryLimit)
        cache = Array(visible)
        return Array(visible)
    }

    func add(result: String, actionLabel: String, provider: UserSettings.Provider, model: String,
             selectedWordCount: Int, imageFileNames: [String]) throws {
        let entry = Entry(id: UUID(), createdAt: Date(), actionLabel: actionLabel, provider: provider.shortLabel,
                          model: model, selectedWordCount: selectedWordCount, hadImages: !imageFileNames.isEmpty,
                          imageFileNames: imageFileNames, result: result)
        try FileManager.default.createDirectory(at: entriesDirectory, withIntermediateDirectories: true)
        let timestamp = String(format: "%020.6f", entry.createdAt.timeIntervalSince1970)
        let file = entriesDirectory.appendingPathComponent("\(timestamp)-\(entry.id.uuidString).json")
        try encoder.encode(entry).write(to: file, options: .atomic)
        if var current = cache {
            current.insert(entry, at: 0)
            cache = Array(current.prefix(Self.visibleEntryLimit))
        }
    }

    // Older entries are never removed automatically; 500 limits only the visible list.
    func clear() throws {
        let archive = directory.appendingPathComponent("cleared-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        for source in [entriesDirectory, directory.appendingPathComponent("history.json")] {
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.moveItem(at: source, to: archive.appendingPathComponent(source.lastPathComponent))
            }
        }
        // An empty current archive prevents historical imports from reappearing.
        try encoder.encode([Entry]()).write(to: directory.appendingPathComponent("history.json"), options: .atomic)
        cache = []
    }
}
