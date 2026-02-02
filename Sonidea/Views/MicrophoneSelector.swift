//
//  MicrophoneSelector.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI
import AVFoundation

struct MicrophoneSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack {
            List {
                // Automatic option
                Button {
                    selectInput(uid: nil)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.body)
                            .foregroundStyle(palette.accent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic")
                                .font(.body)
                                .foregroundStyle(palette.textPrimary)
                            Text("System chooses best available")
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                        }

                        Spacer()

                        if appState.appSettings.preferredInputUID == nil {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(palette.cardBackground)

                // Available inputs section
                Section {
                    ForEach(AudioSessionManager.shared.availableInputs, id: \.uid) { input in
                        Button {
                            selectInput(uid: input.uid)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: AudioSessionManager.icon(for: input.portType))
                                    .font(.body)
                                    .foregroundStyle(palette.accent)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(input.portName)
                                        .font(.body)
                                        .foregroundStyle(palette.textPrimary)
                                    Text(AudioSessionManager.portTypeName(for: input.portType))
                                        .font(.caption)
                                        .foregroundStyle(palette.textSecondary)
                                }

                                Spacer()

                                if appState.appSettings.preferredInputUID == input.uid {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(palette.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(palette.cardBackground)
                    }
                } header: {
                    Text("Available Inputs")
                        .foregroundStyle(palette.textSecondary)
                }

                // Show previously selected but unavailable input
                if let preferredUID = appState.appSettings.preferredInputUID,
                   !AudioSessionManager.shared.isInputAvailable(uid: preferredUID) {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.body)
                                .foregroundStyle(.orange)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Selected microphone")
                                    .font(.body)
                                    .foregroundStyle(palette.textPrimary)
                                Text("Not connected")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            Spacer()

                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(palette.accent)
                        }
                        .listRowBackground(palette.cardBackground)
                    } header: {
                        Text("Previously Selected")
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("Microphone Input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(palette.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Refresh available inputs when sheet appears
            AudioSessionManager.shared.refreshAvailableInputs()
        }
    }

    private func selectInput(uid: String?) {
        appState.appSettings.preferredInputUID = uid

        // Apply the preference immediately if possible
        do {
            try AudioSessionManager.shared.setPreferredInput(uid: uid)
        } catch {
            #if DEBUG
            print("Failed to set preferred input: \(error)")
            #endif
        }

        dismiss()
    }
}
