//
//  Tag.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

struct Tag: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    // MARK: - Protected Tag System

    /// The stable UUID for the "favorite" tag - this never changes
    static let favoriteTagID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Protected tags cannot be deleted or renamed
    var isProtected: Bool {
        id == Tag.favoriteTagID
    }

    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    // Default tags - favorite uses the stable ID
    static let defaultTags: [Tag] = [
        Tag(id: favoriteTagID, name: "favorite", colorHex: "#FF6B6B"),
        Tag(name: "beatbox", colorHex: "#4ECDC4"),
        Tag(name: "melody", colorHex: "#9B59B6"),
        Tag(name: "lyrics", colorHex: "#F39C12")
    ]
}

// MARK: - Color Extension for Hex
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        guard let components = UIColor(self).cgColor.components else { return "#007AFF" }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
