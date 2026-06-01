import Foundation

struct Pinboard: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var symbol: String
    var colorName: String

    init(id: UUID = UUID(), name: String, symbol: String, colorName: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorName = colorName
    }
}

enum LibraryScope: Hashable {
    case all
    case favorites
    case kind(ClipboardKind)
    case pinboard(UUID)

    var title: String {
        switch self {
        case .all: "All Clips"
        case .favorites: "Favorites"
        case .kind(let kind): kind.label
        case .pinboard: "Pinboard"
        }
    }
}
