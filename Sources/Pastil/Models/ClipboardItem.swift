import Foundation

enum ClipboardKind: String, Codable, CaseIterable, Identifiable {
    case text
    case link
    case code
    case file
    case image
    case color

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: "Text"
        case .link: "Link"
        case .code: "Code"
        case .file: "File"
        case .image: "Image"
        case .color: "Color"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .code: "curlybraces"
        case .file: "doc"
        case .image: "photo"
        case .color: "paintpalette"
        }
    }
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: ClipboardKind
    var content: String
    var imageData: Data?
    var appIconData: Data?
    var sourceAppName: String
    var sourceBundleIdentifier: String?
    var createdAt: Date
    var lastUsedAt: Date?
    var useCount: Int
    var isFavorite: Bool
    var pinboardIDs: Set<UUID>

    init(
        id: UUID = UUID(),
        kind: ClipboardKind,
        content: String,
        imageData: Data? = nil,
        appIconData: Data? = nil,
        sourceAppName: String,
        sourceBundleIdentifier: String?,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        useCount: Int = 0,
        isFavorite: Bool = false,
        pinboardIDs: Set<UUID> = []
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.imageData = imageData
        self.appIconData = appIconData
        self.sourceAppName = sourceAppName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.isFavorite = isFavorite
        self.pinboardIDs = pinboardIDs
    }

    var title: String {
        switch kind {
        case .image:
            "Image from \(sourceAppName)"
        case .file:
            URL(fileURLWithPath: content).lastPathComponent
        case .link:
            URL(string: content)?.host(percentEncoded: false) ?? content
        case .color:
            content.uppercased()
        case .code, .text:
            content.trimmingCharacters(in: .whitespacesAndNewlines).firstLineFallback("Untitled Clip")
        }
    }

    var searchCorpus: String {
        "\(content) \(sourceAppName) \(kind.label)"
    }
}

extension String {
    func firstLineFallback(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line = trimmed.split(whereSeparator: \.isNewline).first else {
            return fallback
        }
        return String(line)
    }
}
