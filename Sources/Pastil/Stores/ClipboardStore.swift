import AppKit
import Foundation

final class ClipboardStore: ObservableObject {
    @Published var items: [ClipboardItem] = [] {
        didSet { scheduleSave(); refreshVisibleItems() }
    }
    @Published var pinboards: [Pinboard] = [
        Pinboard(name: "Work", symbol: "briefcase", colorName: "sky"),
        Pinboard(name: "Ideas", symbol: "sparkles", colorName: "gold"),
        Pinboard(name: "Personal", symbol: "person.crop.circle", colorName: "mint")
    ] {
        didSet { scheduleSave(); refreshVisibleItems() }
    }
    @Published var searchText = "" {
        didSet { refreshVisibleItems() }
    }
    @Published var selectedScope: LibraryScope = .all {
        didSet { refreshVisibleItems() }
    }
    @Published var excludedBundleIDs: Set<String> = [
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7"
    ] {
        didSet { scheduleSave() }
    }
    @Published var maximumHistoryCount = 500 {
        didSet { scheduleSave() }
    }
    @Published var captureImages = true {
        didSet { scheduleSave() }
    }

    /// Pre-filtered list the UI binds to, recomputed only when the inputs change
    /// (not on every SwiftUI render).
    @Published private(set) var visibleItems: [ClipboardItem] = []

    private let monitor = ClipboardMonitor()
    private let fileURL: URL
    private let saveQueue = DispatchQueue(label: "com.mohammadreza.Pastil.save", qos: .utility)
    private var pendingSave: DispatchWorkItem?

    init() {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pastil", isDirectory: true)
        fileURL = supportURL.appendingPathComponent("library.json")
        load()
        refreshVisibleItems()
    }

    func startMonitoring() {
        monitor.start { [weak self] item in
            self?.capture(item)
        }
    }

    func copy(_ item: ClipboardItem, paste: Bool = false) {
        markUsed(item)
        if paste {
            monitor.copyAndPaste(item)
        } else {
            monitor.copy(item)
        }
    }

    /// Writes the item's text content as plain text (used for "paste as plain text").
    func copyPlainText(_ item: ClipboardItem) {
        markUsed(item)
        monitor.copyString(item.content)
    }

    func capture(_ item: ClipboardItem) {
        guard item.kind != .image || captureImages else { return }
        guard !isExcluded(item) else { return }

        if let existingIndex = items.firstIndex(where: { $0.kind == item.kind && $0.content == item.content }) {
            var existing = items.remove(at: existingIndex)
            existing.createdAt = Date()
            existing.sourceAppName = item.sourceAppName
            existing.sourceBundleIdentifier = item.sourceBundleIdentifier
            items.insert(existing, at: 0)
        } else {
            items.insert(item, at: 0)
        }

        if items.count > maximumHistoryCount {
            items.removeLast(items.count - maximumHistoryCount)
        }
    }

    func toggleFavorite(_ item: ClipboardItem) {
        update(item) { $0.isFavorite.toggle() }
    }

    func togglePinboard(_ pinboard: Pinboard, for item: ClipboardItem) {
        update(item) { clip in
            if clip.pinboardIDs.contains(pinboard.id) {
                clip.pinboardIDs.remove(pinboard.id)
            } else {
                clip.pinboardIDs.insert(pinboard.id)
            }
        }
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
    }

    func clearUnpinned() {
        items.removeAll { !$0.isFavorite && $0.pinboardIDs.isEmpty }
    }

    func addPinboard(named name: String, colorName: String = "sky") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pinboards.append(Pinboard(name: trimmed, symbol: "pin", colorName: colorName))
    }

    func updatePinboard(_ id: UUID, name: String, colorName: String) {
        guard let index = pinboards.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            pinboards[index].name = trimmed
        }
        pinboards[index].colorName = colorName
    }

    func removePinboard(_ pinboard: Pinboard) {
        pinboards.removeAll { $0.id == pinboard.id }
        // Drop the category from every clip in a single assignment (one save / refresh).
        items = items.map { clip in
            var clip = clip
            clip.pinboardIDs.remove(pinboard.id)
            return clip
        }
        if selectedScope == .pinboard(pinboard.id) {
            selectedScope = .all
        }
    }

    func filteredItems() -> [ClipboardItem] {
        let scoped = items.filter { item in
            switch selectedScope {
            case .all:
                true
            case .favorites:
                item.isFavorite
            case .kind(let kind):
                item.kind == kind
            case .pinboard(let id):
                item.pinboardIDs.contains(id)
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scoped }
        return scoped.filter { $0.searchCorpus.localizedCaseInsensitiveContains(query) }
    }

    func item(for id: ClipboardItem.ID?) -> ClipboardItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    func pinboards(for item: ClipboardItem) -> [Pinboard] {
        pinboards.filter { item.pinboardIDs.contains($0.id) }
    }

    private func refreshVisibleItems() {
        visibleItems = filteredItems()
    }

    /// Mutates an item in place by id. Used by drag-and-drop onto categories.
    func updateItem(id: UUID, _ mutate: (inout ClipboardItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }

    private func update(_ item: ClipboardItem, mutate: (inout ClipboardItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        mutate(&items[index])
    }

    private func markUsed(_ item: ClipboardItem) {
        update(item) {
            $0.useCount += 1
            $0.lastUsedAt = Date()
        }
    }

    private func isExcluded(_ item: ClipboardItem) -> Bool {
        guard let bundleID = item.sourceBundleIdentifier else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let library = try JSONDecoder.pastil.decode(PastilLibrary.self, from: data)
            items = library.items
            pinboards = library.pinboards.isEmpty ? pinboards : library.pinboards
            excludedBundleIDs = library.excludedBundleIDs
            maximumHistoryCount = library.maximumHistoryCount
            captureImages = library.captureImages
        } catch {
            scheduleSave()
        }
    }

    /// Coalesces rapid mutations and writes JSON on a background queue so the main
    /// thread never blocks on encoding/disk I/O (the old cause of the UI jank).
    private func scheduleSave() {
        pendingSave?.cancel()
        let library = PastilLibrary(
            items: items,
            pinboards: pinboards,
            excludedBundleIDs: excludedBundleIDs,
            maximumHistoryCount: maximumHistoryCount,
            captureImages: captureImages
        )
        let url = fileURL
        let work = DispatchWorkItem { Self.write(library, to: url) }
        pendingSave = work
        saveQueue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private static func write(_ library: PastilLibrary, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.pastil.encode(library)
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("Pastil could not save library: \(error.localizedDescription)")
        }
    }
}

private struct PastilLibrary: Codable {
    var items: [ClipboardItem]
    var pinboards: [Pinboard]
    var excludedBundleIDs: Set<String>
    var maximumHistoryCount: Int
    var captureImages: Bool
}

private extension JSONEncoder {
    static var pastil: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var pastil: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
