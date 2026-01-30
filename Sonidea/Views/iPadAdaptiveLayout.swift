//
//  iPadAdaptiveLayout.swift
//  Sonidea
//
//  iPad layout adaptation utilities.
//  Uses horizontalSizeClass so iPad Split View automatically
//  falls back to iPhone layout when narrow.
//

import SwiftUI

// MARK: - iPad Layout Constants

enum iPadLayout {
    static let maxListWidth: CGFloat = 700
    static let maxHUDWidth: CGFloat = 600
}

// MARK: - Adaptive Max Width Modifier

/// Centers content with a max width when `sizeClass == .regular` (iPad full-screen).
/// No-op on iPhone or iPad Split View narrow pane.
struct AdaptiveMaxWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity) // centers within parent
        } else {
            content
        }
    }
}

// MARK: - iPad Full-Screen Sheet Modifiers

/// On iPad (regular size class), presents as fullScreenCover for maximum space.
/// On iPhone (compact size class), presents as a standard sheet.
private struct iPadSheetPresented<SheetContent: View>: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var isPresented: Bool
    @ViewBuilder let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content.fullScreenCover(isPresented: $isPresented, content: sheetContent)
        } else {
            content.sheet(isPresented: $isPresented, content: sheetContent)
        }
    }
}

private struct iPadSheetItem<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var item: Item?
    @ViewBuilder let sheetContent: (Item) -> SheetContent

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content.fullScreenCover(item: $item) { value in sheetContent(value) }
        } else {
            content.sheet(item: $item) { value in sheetContent(value) }
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Constrains width on iPad (regular size class), no-op on iPhone.
    func iPadMaxWidth(_ width: CGFloat = iPadLayout.maxListWidth) -> some View {
        modifier(AdaptiveMaxWidth(maxWidth: width))
    }

    /// Presents as fullScreenCover on iPad, standard sheet on iPhone.
    func iPadSheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(iPadSheetPresented(isPresented: isPresented, sheetContent: content))
    }

    /// Presents as fullScreenCover on iPad, standard sheet on iPhone.
    func iPadSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(iPadSheetItem(item: item, sheetContent: content))
    }
}
