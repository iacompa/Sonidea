//
//  WatchTheme.swift
//  SonideaWatch Watch App
//
//  Subset palette for watchOS matching iOS Theme.swift colors.
//

import SwiftUI

// MARK: - Watch Theme Palette

struct WatchThemePalette: Equatable {
    let background: Color
    let surface: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let recordButton: Color
    let liveRecordingAccent: Color
}

// MARK: - Watch Theme Resolver

enum WatchTheme {
    static func palette(for themeRawValue: String) -> WatchThemePalette {
        switch themeRawValue {
        case "angstRobot":
            return WatchThemePalette(
                background: Color.watchHex("#221B43"),
                surface: Color.watchHex("#2E265A"),
                textPrimary: .white,
                textSecondary: .white.opacity(0.70),
                accent: Color.watchHex("#9B8CFF"),
                recordButton: Color.watchHex("#ED363B"),
                liveRecordingAccent: Color.watchHex("#9B8CFF")
            )
        case "cream":
            return WatchThemePalette(
                background: Color.watchHex("#F6F1E6"),
                surface: Color.watchHex("#FBF7EF"),
                textPrimary: Color.watchHex("#1C1C1E"),
                textSecondary: Color.watchHex("#6B6B70"),
                accent: Color.watchHex("#C4956A"),
                recordButton: Color.watchHex("#ED363B"),
                liveRecordingAccent: Color.watchHex("#C4956A")
            )
        case "logicPro":
            return WatchThemePalette(
                background: Color.watchHex("#2E2E2E"),
                surface: Color.watchHex("#353535"),
                textPrimary: Color.watchHex("#F2F2F7"),
                textSecondary: Color.watchHex("#C7C7CC"),
                accent: Color.watchHex("#7B8AF4"),
                recordButton: Color.watchHex("#ED363B"),
                liveRecordingAccent: Color.watchHex("#7B8AF4")
            )
        case "fruity":
            return WatchThemePalette(
                background: Color.watchHex("#1F2A33"),
                surface: Color.watchHex("#2B3A45"),
                textPrimary: Color.watchHex("#F2F5F7"),
                textSecondary: Color.watchHex("#C0CBD3"),
                accent: Color.watchHex("#F29A2E"),
                recordButton: Color.watchHex("#ED363B"),
                liveRecordingAccent: Color.watchHex("#F29A2E")
            )
        case "avid":
            return WatchThemePalette(
                background: Color.watchHex("#0F1114"),
                surface: Color.watchHex("#1A2027"),
                textPrimary: Color.watchHex("#E9EEF4"),
                textSecondary: Color.watchHex("#AEBBCC"),
                accent: Color.watchHex("#29D3C3"),
                recordButton: Color.watchHex("#ED363B"),
                liveRecordingAccent: Color.watchHex("#29D3C3")
            )
        case "dynamite":
            return WatchThemePalette(
                background: Color.watchHex("#383838"),
                surface: Color.watchHex("#424242"),
                textPrimary: .white,
                textSecondary: .white.opacity(0.70),
                accent: Color.watchHex("#F62E38"),
                recordButton: Color.watchHex("#2786BE"),
                liveRecordingAccent: Color.watchHex("#2786BE")
            )
        default: // "system" and any unknown
            return WatchThemePalette(
                background: Color(.black),
                surface: Color(.darkGray),
                textPrimary: .white,
                textSecondary: .white.opacity(0.60),
                accent: .blue,
                recordButton: Color.watchHex("#ED363B"),
                liveRecordingAccent: .red
            )
        }
    }
}

// MARK: - Color Hex Helper (watchOS)

extension Color {
    static func watchHex(_ hex: String) -> Color {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        return Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Environment Key

private struct WatchPaletteKey: EnvironmentKey {
    static let defaultValue: WatchThemePalette = WatchTheme.palette(for: "system")
}

extension EnvironmentValues {
    var watchPalette: WatchThemePalette {
        get { self[WatchPaletteKey.self] }
        set { self[WatchPaletteKey.self] = newValue }
    }
}
