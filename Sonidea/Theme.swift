//
//  Theme.swift
//  Sonidea
//
//  Centralized theming system with multiple color palettes.
//

import SwiftUI

// MARK: - App Theme Enum

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system
    case angstRobot
    case cream
    case logicPro
    case fruity
    case avid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .angstRobot: return "Angst Robot"
        case .cream: return "Cream"
        case .logicPro: return "Logic"
        case .fruity: return "Fruity"
        case .avid: return "AVID"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "Default iOS appearance"
        case .angstRobot: return "Inspired by Ableton Live AngstRobot"
        case .cream: return "Warm light tones"
        case .logicPro: return "Inspired by Logic Pro."
        case .fruity: return "Inspired by FL Studio."
        case .avid: return "Inspired by Pro Tools."
        }
    }

    /// Returns the appropriate palette for the given color scheme
    func palette(for colorScheme: ColorScheme) -> ThemePalette {
        switch self {
        case .system:
            return colorScheme == .dark ? ThemePalette.systemDark : ThemePalette.systemLight
        case .angstRobot:
            return ThemePalette.angstRobot
        case .cream:
            return ThemePalette.cream
        case .logicPro:
            return ThemePalette.logicPro
        case .fruity:
            return ThemePalette.fruity
        case .avid:
            return ThemePalette.avid
        }
    }

    /// The forced color scheme for this theme (nil = follow system)
    var forcedColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .angstRobot: return .dark
        case .cream: return .light
        case .logicPro: return .dark
        case .fruity: return .dark
        case .avid: return .dark
        }
    }

    /// Whether this theme uses accent color for live recording UI (timer, waveform)
    /// System themes use red; custom themes use their accent color
    var usesAccentForRecording: Bool {
        switch self {
        case .system:
            return false  // System themes keep red
        case .angstRobot, .cream, .logicPro, .fruity, .avid:
            return true   // Custom themes use accent
        }
    }

    /// Whether this is a custom theme (not System)
    /// Custom themes apply explicit toolbar styling
    var isCustomTheme: Bool {
        switch self {
        case .system:
            return false
        case .angstRobot, .cream, .logicPro, .fruity, .avid:
            return true
        }
    }

    /// The color scheme to use for the toolbar (for status bar readability)
    /// Returns nil for System theme (use iOS defaults)
    var toolbarColorSchemeOverride: ColorScheme? {
        switch self {
        case .system:
            return nil  // Use iOS defaults
        case .cream:
            return .light  // Light background needs light scheme (dark status bar)
        case .logicPro:
            return .light  // Light toolbar on dark canvas
        case .angstRobot, .fruity, .avid:
            return .dark   // Dark backgrounds need dark scheme (light status bar)
        }
    }
}

// MARK: - Theme Palette

struct ThemePalette: Equatable {
    // Backgrounds
    let background: Color
    let surface: Color
    let surfaceRaised: Color
    let groupedBackground: Color
    let secondaryGroupedBackground: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    // Separators & Strokes
    let separator: Color
    let stroke: Color

    // Interactive Elements
    let accent: Color         // iOS blue for actions
    let recordButton: Color   // Sonidea red for recording

    // Material override (for sheets and overlays)
    let useMaterials: Bool

    // Semantic colors for specific UI elements
    let listRowBackground: Color
    let cardBackground: Color
    let inputBackground: Color
    let navigationBarBackground: Color
    let sheetBackground: Color

    // Button colors
    let primaryButtonBackground: Color
    let primaryButtonForeground: Color
    let secondaryButtonBackground: Color
    let secondaryButtonForeground: Color

    // Chip colors
    let chipBackground: Color
    let chipForeground: Color
    let chipStroke: Color
    let chipSelectedBackground: Color
    let chipSelectedForeground: Color

    // Control tints
    let sliderTint: Color
    let toggleOnTint: Color

    // Typography settings
    let titleFontDesign: Font.Design
    let numericFontDesign: Font.Design

    // Live recording accent (timer + waveform color while recording)
    // System themes use red; custom themes use their accent
    let liveRecordingAccent: Color

    // Toolbar-specific styling (for themes with contrasting toolbar like Logic Pro)
    let toolbarColorScheme: ColorScheme?  // nil = follow main scheme, .light/.dark = override
    let toolbarTextPrimary: Color?        // nil = use textPrimary
    let toolbarTextSecondary: Color?      // nil = use textSecondary

    // Waveform editor colors
    // Selection background should be visible but subtle - not overpower the waveform
    // Each theme has a curated color to ensure good contrast with waveform bars
    let waveformSelectionBackground: Color

    // Convenience accessors for toolbar text colors
    var effectiveToolbarTextPrimary: Color {
        toolbarTextPrimary ?? textPrimary
    }

    var effectiveToolbarTextSecondary: Color {
        toolbarTextSecondary ?? textSecondary
    }

    // MARK: - System Light Palette

    static let systemLight = ThemePalette(
        background: Color(.systemBackground),
        surface: Color(.secondarySystemBackground),
        surfaceRaised: Color(.tertiarySystemBackground),
        groupedBackground: Color(.systemGroupedBackground),
        secondaryGroupedBackground: Color(.secondarySystemGroupedBackground),
        textPrimary: Color(.label),
        textSecondary: Color(.secondaryLabel),
        textTertiary: Color(.tertiaryLabel),
        separator: Color(.separator),
        stroke: Color(.systemGray4),
        accent: Color.accentColor,
        recordButton: Color.red,
        useMaterials: true,
        listRowBackground: Color.clear,
        cardBackground: Color(.systemBackground),
        inputBackground: Color(.systemGray6),
        navigationBarBackground: Color(.systemBackground),
        sheetBackground: Color(.systemBackground),
        primaryButtonBackground: Color.accentColor,
        primaryButtonForeground: Color.white,
        secondaryButtonBackground: Color(.systemGray5),
        secondaryButtonForeground: Color(.label),
        chipBackground: Color(.systemGray6),
        chipForeground: Color.accentColor,
        chipStroke: Color.accentColor.opacity(0.3),
        chipSelectedBackground: Color.accentColor,
        chipSelectedForeground: Color.white,
        sliderTint: Color.accentColor,
        toggleOnTint: Color.green,
        titleFontDesign: .default,
        numericFontDesign: .monospaced,
        liveRecordingAccent: Color.red,  // System themes use red
        toolbarColorScheme: nil,
        toolbarTextPrimary: nil,
        toolbarTextSecondary: nil,
        waveformSelectionBackground: Color.accentColor.opacity(0.15)  // Subtle blue tint
    )

    // MARK: - System Dark Palette

    static let systemDark = ThemePalette(
        background: Color(.systemBackground),
        surface: Color(.secondarySystemBackground),
        surfaceRaised: Color(.tertiarySystemBackground),
        groupedBackground: Color(.systemGroupedBackground),
        secondaryGroupedBackground: Color(.secondarySystemGroupedBackground),
        textPrimary: Color(.label),
        textSecondary: Color(.secondaryLabel),
        textTertiary: Color(.tertiaryLabel),
        separator: Color(.separator),
        stroke: Color(.systemGray4),
        accent: Color.accentColor,
        recordButton: Color.red,
        useMaterials: true,
        listRowBackground: Color.clear,
        cardBackground: Color(.systemBackground),
        inputBackground: Color(.systemGray6),
        navigationBarBackground: Color(.systemBackground),
        sheetBackground: Color(.systemBackground),
        primaryButtonBackground: Color.accentColor,
        primaryButtonForeground: Color.white,
        secondaryButtonBackground: Color(.systemGray5),
        secondaryButtonForeground: Color(.label),
        chipBackground: Color(.systemGray6),
        chipForeground: Color.accentColor,
        chipStroke: Color.accentColor.opacity(0.3),
        chipSelectedBackground: Color.accentColor,
        chipSelectedForeground: Color.white,
        sliderTint: Color.accentColor,
        toggleOnTint: Color.green,
        titleFontDesign: .default,
        numericFontDesign: .monospaced,
        liveRecordingAccent: Color.red,  // System themes use red
        toolbarColorScheme: nil,
        toolbarTextPrimary: nil,
        toolbarTextSecondary: nil,
        waveformSelectionBackground: Color.accentColor.opacity(0.20)  // Slightly more visible on dark
    )

    // MARK: - Angst Robot (Purple) Palette

    static let angstRobot = ThemePalette(
        background: Color.fromHex("#221B43"),
        surface: Color.fromHex("#2E265A"),
        surfaceRaised: Color.fromHex("#332A65"),
        groupedBackground: Color.fromHex("#1A1433"),
        secondaryGroupedBackground: Color.fromHex("#2E265A"),
        textPrimary: Color.white,
        textSecondary: Color.white.opacity(0.70),
        textTertiary: Color.white.opacity(0.50),
        separator: Color.fromHex("#444687"),
        stroke: Color.fromHex("#444687"),
        accent: Color.fromHex("#9B8CFF"),  // Light purple accent
        recordButton: Color.fromHex("#FF6B6B"),  // Coral red
        useMaterials: false,
        listRowBackground: Color.clear,  // Clear so background shows through uniformly
        cardBackground: Color.fromHex("#2E265A"),
        inputBackground: Color.fromHex("#332A65"),
        navigationBarBackground: Color.fromHex("#221B43"),
        sheetBackground: Color.fromHex("#2E265A"),
        primaryButtonBackground: Color.fromHex("#9B8CFF"),  // Light purple
        primaryButtonForeground: Color.fromHex("#1A1433"),  // Dark purple text
        secondaryButtonBackground: Color.fromHex("#3D3470"),  // Muted purple
        secondaryButtonForeground: Color.white.opacity(0.90),
        chipBackground: Color.fromHex("#332A65"),
        chipForeground: Color.fromHex("#9B8CFF"),
        chipStroke: Color.fromHex("#9B8CFF").opacity(0.4),
        chipSelectedBackground: Color.fromHex("#9B8CFF"),
        chipSelectedForeground: Color.fromHex("#1A1433"),
        sliderTint: Color.fromHex("#9B8CFF"),
        toggleOnTint: Color.fromHex("#7B6BDF"),  // Muted purple toggle
        titleFontDesign: .rounded,  // Rounded titles for Ableton-inspired look
        numericFontDesign: .monospaced,
        liveRecordingAccent: Color.fromHex("#9B8CFF"),  // Purple accent for recording UI
        toolbarColorScheme: nil,
        toolbarTextPrimary: nil,
        toolbarTextSecondary: nil,
        waveformSelectionBackground: Color.fromHex("#9B8CFF").opacity(0.18)  // Light purple selection
    )

    // MARK: - Cream (Russian White) Palette

    static let cream = ThemePalette(
        background: Color.fromHex("#F6F1E6"),
        surface: Color.fromHex("#FBF7EF"),
        surfaceRaised: Color.fromHex("#F0E9DC"),
        groupedBackground: Color.fromHex("#EDE6D9"),
        secondaryGroupedBackground: Color.fromHex("#FBF7EF"),
        textPrimary: Color.fromHex("#1C1C1E"),
        textSecondary: Color.fromHex("#6B6B70"),
        textTertiary: Color.fromHex("#8E8E93"),
        separator: Color.fromHex("#D8D0C2"),
        stroke: Color.fromHex("#D8D0C2"),
        accent: Color.fromHex("#C4956A"),  // Warm amber/brown accent
        recordButton: Color.fromHex("#D4644A"),  // Warm terracotta red
        useMaterials: false,
        listRowBackground: Color.clear,  // Clear so background shows through uniformly
        cardBackground: Color.fromHex("#FFFFFF"),
        inputBackground: Color.fromHex("#F0E9DC"),
        navigationBarBackground: Color.fromHex("#F6F1E6"),
        sheetBackground: Color.fromHex("#FBF7EF"),
        primaryButtonBackground: Color.fromHex("#C4956A"),  // Warm amber
        primaryButtonForeground: Color.white,
        secondaryButtonBackground: Color.fromHex("#E8E0D0"),  // Light tan
        secondaryButtonForeground: Color.fromHex("#5A5A5E"),
        chipBackground: Color.fromHex("#F0E9DC"),
        chipForeground: Color.fromHex("#C4956A"),
        chipStroke: Color.fromHex("#C4956A").opacity(0.3),
        chipSelectedBackground: Color.fromHex("#C4956A"),
        chipSelectedForeground: Color.white,
        sliderTint: Color.fromHex("#C4956A"),
        toggleOnTint: Color.fromHex("#8DAD7F"),  // Sage green toggle
        titleFontDesign: .default,  // Standard serif/sans for classic look
        numericFontDesign: .monospaced,
        liveRecordingAccent: Color.fromHex("#C4956A"),  // Warm amber accent for recording UI
        toolbarColorScheme: nil,
        toolbarTextPrimary: nil,
        toolbarTextSecondary: nil,
        waveformSelectionBackground: Color.fromHex("#C4956A").opacity(0.12)  // Subtle amber on light bg
    )

    // MARK: - Logic Pro Palette (Light toolbar + Dark canvas)

    static let logicPro = ThemePalette(
        // Dark canvas backgrounds
        background: Color.fromHex("#2E2E2E"),           // screenBackground - main canvas charcoal
        surface: Color.fromHex("#353535"),              // surface1 - primary card/list
        surfaceRaised: Color.fromHex("#3A3A3C"),        // surface2 - elevated card/sheet
        groupedBackground: Color.fromHex("#2E2E2E"),    // screenBackground
        secondaryGroupedBackground: Color.fromHex("#353535"),  // surface1

        // Text on dark surfaces
        textPrimary: Color.fromHex("#F2F2F7"),          // iOS primary on dark
        textSecondary: Color.fromHex("#C7C7CC"),        // iOS secondary on dark
        textTertiary: Color.fromHex("#8E8E93"),         // tertiary on dark

        // Separators & Strokes
        separator: Color.fromHex("#4A4A4D"),            // subtle dividers on dark
        stroke: Color.fromHex("#4A4A4D"),

        // Accent (Logic-like periwinkle)
        accent: Color.fromHex("#7B8AF4"),               // periwinkle / selection highlight
        recordButton: Color.fromHex("#FF3B30"),         // standard iOS record red

        useMaterials: false,

        // Semantic colors
        listRowBackground: Color.clear,
        cardBackground: Color.fromHex("#353535"),       // surface1
        inputBackground: Color.fromHex("#3A3A3C"),      // surface2
        navigationBarBackground: Color.fromHex("#C7C9CE"),  // Light toolbar background
        sheetBackground: Color.fromHex("#3A3A3C"),      // surface2

        // Button colors
        primaryButtonBackground: Color.fromHex("#7B8AF4"),  // accentPrimary
        primaryButtonForeground: Color.white,
        secondaryButtonBackground: Color.fromHex("#3A3A3C"),  // surface2
        secondaryButtonForeground: Color.fromHex("#7B8AF4"),  // accentPrimary

        // Chip colors
        chipBackground: Color.fromHex("#3A3A3C"),
        chipForeground: Color.fromHex("#7B8AF4"),
        chipStroke: Color.fromHex("#7B8AF4").opacity(0.3),
        chipSelectedBackground: Color.fromHex("#7B8AF4"),
        chipSelectedForeground: Color.white,

        // Control tints
        sliderTint: Color.fromHex("#7B8AF4"),
        toggleOnTint: Color.fromHex("#7259A4"),         // accentSecondary blue-violet

        // Typography
        titleFontDesign: .default,
        numericFontDesign: .monospaced,

        liveRecordingAccent: Color.fromHex("#7B8AF4"),  // Periwinkle accent for recording UI

        // Logic Pro has a LIGHT toolbar on dark canvas
        toolbarColorScheme: .light,
        toolbarTextPrimary: Color.fromHex("#1C1C1E"),   // dark text on light toolbar
        toolbarTextSecondary: Color.fromHex("#3A3A3C"),
        waveformSelectionBackground: Color.fromHex("#7B8AF4").opacity(0.20)  // Periwinkle selection
    )

    // MARK: - Fruity (FL Studio) Palette

    static let fruity = ThemePalette(
        // FL-style cool dark backgrounds
        background: Color.fromHex("#1F2A33"),           // screenBackground - deep blue-gray base
        surface: Color.fromHex("#2B3A45"),              // surface1 - primary card/list row
        surfaceRaised: Color.fromHex("#30414D"),        // surface2 - elevated panels/sheets
        groupedBackground: Color.fromHex("#1F2A33"),    // screenBackground
        secondaryGroupedBackground: Color.fromHex("#2B3A45"),  // surface1

        // Text on dark surfaces
        textPrimary: Color.fromHex("#F2F5F7"),
        textSecondary: Color.fromHex("#C0CBD3"),
        textTertiary: Color.fromHex("#8FA0AB"),

        // Separators & Strokes
        separator: Color.fromHex("#3E5563"),
        stroke: Color.fromHex("#3E5563"),

        // FL orange accent
        accent: Color.fromHex("#F29A2E"),               // FL orange highlight
        recordButton: Color.fromHex("#FF3B30"),         // standard iOS record red

        useMaterials: false,

        // Semantic colors
        listRowBackground: Color.clear,
        cardBackground: Color.fromHex("#2B3A45"),       // surface1
        inputBackground: Color.fromHex("#30414D"),      // surface2
        navigationBarBackground: Color.fromHex("#465662"),  // cool gray-blue chrome toolbar
        sheetBackground: Color.fromHex("#30414D"),      // surface2

        // Button colors
        primaryButtonBackground: Color.fromHex("#F29A2E"),  // FL orange
        primaryButtonForeground: Color.white,
        secondaryButtonBackground: Color.fromHex("#30414D"),  // surface2
        secondaryButtonForeground: Color.fromHex("#F29A2E"),  // FL orange

        // Chip colors
        chipBackground: Color.fromHex("#30414D"),
        chipForeground: Color.fromHex("#F29A2E"),
        chipStroke: Color.fromHex("#F29A2E").opacity(0.3),
        chipSelectedBackground: Color.fromHex("#F29A2E"),
        chipSelectedForeground: Color.fromHex("#1F2A33"),   // dark text on orange

        // Control tints
        sliderTint: Color.fromHex("#F29A2E"),
        toggleOnTint: Color.fromHex("#39B6C8"),         // cool teal for toggles

        // Typography
        titleFontDesign: .default,
        numericFontDesign: .monospaced,

        liveRecordingAccent: Color.fromHex("#F29A2E"),  // FL orange for recording UI

        // Dark toolbar matching the overall dark scheme
        toolbarColorScheme: nil,
        toolbarTextPrimary: Color.fromHex("#F2F5F7"),
        toolbarTextSecondary: Color.fromHex("#C9D2D8"),
        waveformSelectionBackground: Color.fromHex("#F29A2E").opacity(0.15)  // Subtle orange selection
    )

    // MARK: - AVID (Pro Tools) Palette

    static let avid = ThemePalette(
        // Pro Tools graphite / dark slate backgrounds
        background: Color.fromHex("#0F1114"),           // screenBackground - near-black graphite
        surface: Color.fromHex("#1A2027"),              // surface1 - primary cards/list rows
        surfaceRaised: Color.fromHex("#202833"),        // surface2 - elevated panels/sheets
        groupedBackground: Color.fromHex("#0F1114"),    // screenBackground
        secondaryGroupedBackground: Color.fromHex("#1A2027"),  // surface1

        // Text
        textPrimary: Color.fromHex("#E9EEF4"),
        textSecondary: Color.fromHex("#AEBBCC"),
        textTertiary: Color.fromHex("#7E8A98"),

        // Separators & Strokes
        separator: Color.fromHex("#2C3746"),
        stroke: Color.fromHex("#2C3746"),

        // Teal/mint accent (Pro Tools LED vibe)
        accent: Color.fromHex("#29D3C3"),               // teal/mint highlight
        recordButton: Color.fromHex("#FF3B30"),         // standard iOS record red

        useMaterials: false,

        // Semantic colors
        listRowBackground: Color.clear,
        cardBackground: Color.fromHex("#1A2027"),       // surface1
        inputBackground: Color.fromHex("#202833"),      // surface2
        navigationBarBackground: Color.fromHex("#141A21"),  // dark toolbar
        sheetBackground: Color.fromHex("#202833"),      // surface2

        // Button colors (dark text on teal for contrast)
        primaryButtonBackground: Color.fromHex("#29D3C3"),  // teal/mint
        primaryButtonForeground: Color.fromHex("#0F1114"), // dark text on teal
        secondaryButtonBackground: Color.fromHex("#202833"),  // surface2
        secondaryButtonForeground: Color.fromHex("#29D3C3"),  // teal

        // Chip colors
        chipBackground: Color.fromHex("#202833"),
        chipForeground: Color.fromHex("#29D3C3"),
        chipStroke: Color.fromHex("#29D3C3").opacity(0.3),
        chipSelectedBackground: Color.fromHex("#29D3C3"),
        chipSelectedForeground: Color.fromHex("#0F1114"),   // dark text on teal

        // Control tints
        sliderTint: Color.fromHex("#29D3C3"),
        toggleOnTint: Color.fromHex("#3EA0FF"),         // cool blue for toggles

        // Typography
        titleFontDesign: .default,
        numericFontDesign: .monospaced,

        liveRecordingAccent: Color.fromHex("#29D3C3"),  // Teal/mint for recording UI

        // Dark toolbar matching the overall dark scheme
        toolbarColorScheme: nil,
        toolbarTextPrimary: Color.fromHex("#E9EEF4"),
        toolbarTextSecondary: Color.fromHex("#AEBBCC"),
        waveformSelectionBackground: Color.fromHex("#29D3C3").opacity(0.18)  // Teal selection
    )
}

// MARK: - Color Hex Helper

extension Color {
    /// Create a Color from a hex string (non-failable, defaults to black on invalid input)
    /// This variant is used for theme palettes where we control the input.
    static func fromHex(_ hex: String) -> Color {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
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

// MARK: - Environment Key for Theme Palette

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue: ThemePalette = .systemLight
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .system
}

extension EnvironmentValues {
    var themePalette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }

    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - View Extension for Theme

extension View {
    /// Apply the theme palette as an environment value
    func themePalette(_ palette: ThemePalette) -> some View {
        environment(\.themePalette, palette)
    }

    /// Apply the app theme
    func appTheme(_ theme: AppTheme) -> some View {
        environment(\.appTheme, theme)
    }
}

// MARK: - Themed Background Modifier

struct ThemedBackground: ViewModifier {
    @Environment(\.themePalette) var palette

    func body(content: Content) -> some View {
        content
            .background(palette.background.ignoresSafeArea())
    }
}

extension View {
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }
}

// MARK: - Themed List Row Background

struct ThemedListRowBackground: ViewModifier {
    @Environment(\.themePalette) var palette

    func body(content: Content) -> some View {
        content
            .listRowBackground(palette.listRowBackground)
    }
}

extension View {
    func themedListRowBackground() -> some View {
        modifier(ThemedListRowBackground())
    }
}

// MARK: - Themed Card

struct ThemedCard<Content: View>: View {
    @Environment(\.themePalette) var palette
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(palette.cardBackground)
            .cornerRadius(12)
    }
}

// MARK: - Themed Input Background

struct ThemedInputBackground: ViewModifier {
    @Environment(\.themePalette) var palette

    func body(content: Content) -> some View {
        content
            .background(palette.inputBackground)
            .cornerRadius(8)
    }
}

extension View {
    func themedInputBackground() -> some View {
        modifier(ThemedInputBackground())
    }
}
