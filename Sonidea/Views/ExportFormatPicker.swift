//
//  ExportFormatPicker.swift
//  Sonidea
//
//  Sheet for choosing an export format before sharing a recording.
//

import SwiftUI

// MARK: - Bulk Export Format Picker (multi-select checkboxes)

struct BulkExportFormatPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    @State private var selectedFormats: Set<ExportFormat> = [.original, .wav]
    let onExport: (Set<ExportFormat>) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ExportFormat.allCases) { format in
                        Button {
                            if selectedFormats.contains(format) {
                                selectedFormats.remove(format)
                            } else {
                                selectedFormats.insert(format)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: selectedFormats.contains(format) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 20))
                                    .foregroundColor(selectedFormats.contains(format) ? palette.accent : palette.textSecondary)
                                    .frame(width: 28, alignment: .center)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(format.displayName)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(palette.textPrimary)
                                    Text(format.subtitle)
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Select Formats")
                } footer: {
                    if selectedFormats.count > 1 {
                        Text("Each format will be exported in its own sub-folder inside the ZIP.")
                            .foregroundColor(palette.textSecondary)
                    }
                }
            }
            .navigationTitle("Bulk Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Export") {
                        dismiss()
                        onExport(selectedFormats)
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedFormats.isEmpty)
                }
            }
        }
    }
}

// MARK: - Single Export Format Picker

struct ExportFormatPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    let onSelect: (ExportFormat) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ExportFormat.allCases) { format in
                        Button {
                            dismiss()
                            onSelect(format)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: format.iconName)
                                    .font(.system(size: 20))
                                    .foregroundColor(palette.accent)
                                    .frame(width: 28, alignment: .center)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(format.displayName)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(palette.textPrimary)
                                    Text(format.subtitle)
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Choose Format")
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
