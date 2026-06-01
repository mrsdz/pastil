import SwiftUI

extension Color {
    static let pastilMint = Color(red: 0.23, green: 0.76, blue: 0.58)
    static let pastilCoral = Color(red: 0.95, green: 0.40, blue: 0.35)
    static let pastilGold = Color(red: 0.96, green: 0.72, blue: 0.30)
    static let pastilSky = Color(red: 0.30, green: 0.58, blue: 0.95)
    static let pastilPurple = Color(red: 0.58, green: 0.40, blue: 0.92)
    static let pastilPink = Color(red: 0.95, green: 0.42, blue: 0.66)
    static let pastilTeal = Color(red: 0.16, green: 0.70, blue: 0.69)
    static let pastilIndigo = Color(red: 0.35, green: 0.42, blue: 0.90)
    static let pastilInk = Color(red: 0.12, green: 0.13, blue: 0.17)

    /// Selectable category colors, in the order shown in the picker.
    static let pinboardColorNames = ["sky", "mint", "gold", "coral", "purple", "pink", "teal", "indigo"]

    static func pinboard(_ name: String) -> Color {
        switch name {
        case "mint": .pastilMint
        case "coral": .pastilCoral
        case "gold": .pastilGold
        case "sky": .pastilSky
        case "purple": .pastilPurple
        case "pink": .pastilPink
        case "teal": .pastilTeal
        case "indigo": .pastilIndigo
        default: .accentColor
        }
    }

    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }

        guard let value = Int(text, radix: 16) else { return nil }

        switch text.count {
        case 3:
            let r = Double((value >> 8) & 0xF) / 15
            let g = Double((value >> 4) & 0xF) / 15
            let b = Double(value & 0xF) / 15
            self = Color(red: r, green: g, blue: b)
        case 6, 8:
            let r = Double((value >> (text.count == 8 ? 24 : 16)) & 0xFF) / 255
            let g = Double((value >> (text.count == 8 ? 16 : 8)) & 0xFF) / 255
            let b = Double((value >> (text.count == 8 ? 8 : 0)) & 0xFF) / 255
            self = Color(red: r, green: g, blue: b)
        default:
            return nil
        }
    }
}
