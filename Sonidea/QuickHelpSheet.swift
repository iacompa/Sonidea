//
//  QuickHelpSheet.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

/// A reusable help sheet that displays setup instructions with action buttons
struct QuickHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let icon: String
    let steps: [String]
    let primaryButtonTitle: String
    let primaryAction: () -> Void
    var secondaryButtonTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
                // Header section with icon
                Section {
                    HStack {
                        Spacer()
                        Image(systemName: icon)
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                // Steps section
                Section {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1).")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.accentColor)
                                .frame(width: 24, alignment: .leading)

                            Text(step)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Setup Steps")
                }

                // Action buttons section
                Section {
                    Button {
                        primaryAction()
                    } label: {
                        HStack {
                            Spacer()
                            Text(primaryButtonTitle)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }

                    if let secondaryTitle = secondaryButtonTitle,
                       let secondaryAction = secondaryAction {
                        Button {
                            secondaryAction()
                        } label: {
                            HStack {
                                Spacer()
                                Text(secondaryTitle)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preset Help Sheets

/// Help sheet for Lock Screen Widget setup
struct LockScreenWidgetHelpSheet: View {
    var body: some View {
        QuickHelpSheet(
            title: "Lock Screen Widget",
            icon: "lock.rectangle.on.rectangle",
            steps: [
                "Long-press on your Lock Screen to enter edit mode",
                "Tap \"Customize\" below the clock",
                "Tap the area above or below the time to add widgets",
                "Search for \"Sonidea\" or scroll to find it",
                "Select the \"Record\" widget",
                "Tap \"Done\" to save"
            ],
            primaryButtonTitle: "Open App Settings",
            primaryAction: {
                DeepLinks.openAppSettings()
            }
        )
    }
}

/// Help sheet for Action Button setup
struct ActionButtonHelpSheet: View {
    var body: some View {
        QuickHelpSheet(
            title: "Action Button",
            icon: "button.horizontal.top.press",
            steps: [
                "Open the Settings app on your iPhone",
                "Scroll down and tap \"Action Button\"",
                "Swipe to select \"Shortcut\"",
                "Tap \"Choose a Shortcut\"",
                "Search for \"Start Recording\" or \"Sonidea\"",
                "Select the shortcut to assign it"
            ],
            primaryButtonTitle: "Open App Settings",
            primaryAction: {
                DeepLinks.openAppSettings()
            },
            secondaryButtonTitle: "Open Shortcuts",
            secondaryAction: {
                DeepLinks.openShortcutsApp()
            }
        )
    }
}

/// Help sheet for Siri & Shortcuts setup
struct SiriShortcutsHelpSheet: View {
    var body: some View {
        QuickHelpSheet(
            title: "Siri & Shortcuts",
            icon: "mic.badge.plus",
            steps: [
                "Open the Shortcuts app",
                "Tap \"+\" to create a new shortcut",
                "Tap \"Add Action\"",
                "Search for \"Sonidea\"",
                "Select \"Start Recording\"",
                "Tap the shortcut name to rename it (e.g., \"Record\")",
                "Say \"Hey Siri, Record\" to start recording"
            ],
            primaryButtonTitle: "Open Shortcuts",
            primaryAction: {
                DeepLinks.openShortcutsApp()
            },
            secondaryButtonTitle: "Open App Settings",
            secondaryAction: {
                DeepLinks.openAppSettings()
            }
        )
    }
}
