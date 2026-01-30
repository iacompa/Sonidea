//
//  ExportFormatPicker.swift
//  Sonidea
//
//  Sheet for choosing an export format before sharing a recording.
//

import SwiftUI

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
