//
//  TagManagerView.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

struct TagManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    @State private var searchQuery = ""
    @State private var isEditMode = false
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var showCreateTag = false
    @State private var editingTag: Tag?
    @State private var showMergeSheet = false
    @State private var showDeleteProtectedAlert = false
    @State private var proUpgradeContext: ProFeatureContext? = nil
    @State private var showTipJar = false

    private var filteredTags: [Tag] {
        if searchQuery.isEmpty {
            return appState.tags
        }
        return appState.tags.filter { $0.name.lowercased().contains(searchQuery.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search tags...", text: $searchQuery)
                        .foregroundColor(.primary)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 8)

                // Tip line
                Text("Tip: Swipe to delete, tap to edit color and name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Tag list
                List {
                    ForEach(filteredTags) { tag in
                        TagManagerRow(
                            tag: tag,
                            usageCount: appState.tagUsageCount(tag),
                            isSelected: selectedTagIDs.contains(tag.id),
                            isEditMode: isEditMode
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isEditMode {
                                toggleSelection(tag)
                            } else {
                                guard appState.supportManager.canUseProFeatures else {
                                    proUpgradeContext = .tags
                                    return
                                }
                                editingTag = tag
                            }
                        }
                    }
                    .onDelete { offsets in
                        deleteTagsAt(offsets)
                    }
                    .onMove { source, destination in
                        appState.moveTag(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(isEditMode ? .active : .inactive))

                // Bottom toolbar for batch actions
                if isEditMode && !selectedTagIDs.isEmpty {
                    batchActionBar
                }
            }
            .navigationTitle("Manage Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isEditMode ? "Done" : "Select") {
                        withAnimation {
                            isEditMode.toggle()
                            if !isEditMode {
                                selectedTagIDs.removeAll()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button {
                            guard appState.supportManager.canUseProFeatures else {
                                proUpgradeContext = .tags
                                return
                            }
                            showCreateTag = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        Button("Done") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showCreateTag) {
                CreateTagSheet()
            }
            .sheet(item: $editingTag) { tag in
                TagEditSheet(tag: tag)
            }
            .sheet(isPresented: $showMergeSheet) {
                MergeTagsSheet(selectedTagIDs: selectedTagIDs) {
                    selectedTagIDs.removeAll()
                    isEditMode = false
                }
            }
            .alert("Cannot Delete", isPresented: $showDeleteProtectedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The \"favorite\" tag is protected and cannot be deleted.")
            }
            .sheet(item: $proUpgradeContext) { context in
                ProUpgradeSheet(
                    context: context,
                    onViewPlans: {
                        proUpgradeContext = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showTipJar = true
                        }
                    },
                    onDismiss: {
                        proUpgradeContext = nil
                    }
                )
                .environment(\.themePalette, palette)
            }
            .sheet(isPresented: $showTipJar) {
                TipJarView()
                    .environment(appState)
                    .environment(\.themePalette, palette)
            }
        }
    }

    private var batchActionBar: some View {
        HStack {
            Button {
                showMergeSheet = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.merge")
                    Text("Merge")
                        .font(.caption)
                }
            }
            .disabled(selectedTagIDs.count < 2)

            Spacer()

            Text("\(selectedTagIDs.count) selected")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Button(role: .destructive) {
                deleteSelectedTags()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Delete")
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }

    private func toggleSelection(_ tag: Tag) {
        if selectedTagIDs.contains(tag.id) {
            selectedTagIDs.remove(tag.id)
        } else {
            selectedTagIDs.insert(tag.id)
        }
    }

    private func deleteTagsAt(_ offsets: IndexSet) {
        for index in offsets {
            let tag = filteredTags[index]
            if tag.isProtected {
                showDeleteProtectedAlert = true
            } else {
                _ = appState.deleteTag(tag)
            }
        }
    }

    private func deleteSelectedTags() {
        var hasProtected = false
        for tagID in selectedTagIDs {
            if let tag = appState.tag(for: tagID) {
                if tag.isProtected {
                    hasProtected = true
                } else {
                    _ = appState.deleteTag(tag)
                }
            }
        }
        selectedTagIDs.removeAll()
        if hasProtected {
            showDeleteProtectedAlert = true
        }
    }
}

// MARK: - Tag Manager Row

struct TagManagerRow: View {
    let tag: Tag
    let usageCount: Int
    let isSelected: Bool
    let isEditMode: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
            }

            Circle()
                .fill(tag.color)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(tag.name)
                        .font(.body)
                        .fontWeight(.medium)

                    if tag.isProtected {
                        Text("SYSTEM")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                Text("\(usageCount) recording\(usageCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isEditMode {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create Tag Sheet

struct CreateTagSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var tagName = ""
    @State private var tagColor = Color.blue
    @State private var showDuplicateError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tag name", text: $tagName)
                        .onChange(of: tagName) { _, _ in
                            showDuplicateError = false
                        }

                    ColorPicker("Color", selection: $tagColor, supportsOpacity: false)
                }

                if showDuplicateError {
                    Section {
                        Text("A tag with this name already exists.")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createTag()
                    }
                    .disabled(tagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func createTag() {
        let trimmedName = tagName.trimmingCharacters(in: .whitespaces)
        if appState.createTag(name: trimmedName, colorHex: tagColor.toHex()) != nil {
            dismiss()
        } else {
            showDuplicateError = true
        }
    }
}

// MARK: - Tag Edit Sheet

struct TagEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let tag: Tag

    @State private var tagName: String
    @State private var tagColor: Color
    @State private var showDuplicateError = false
    @State private var showDeleteProtectedAlert = false

    init(tag: Tag) {
        self.tag = tag
        _tagName = State(initialValue: tag.name)
        _tagColor = State(initialValue: tag.color)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if tag.isProtected {
                        // Protected tags cannot be renamed
                        HStack {
                            Text("Name")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(tag.name)
                                .foregroundColor(.primary)
                        }
                    } else {
                        TextField("Tag name", text: $tagName)
                            .onChange(of: tagName) { _, _ in
                                showDuplicateError = false
                            }
                    }

                    ColorPicker("Color", selection: $tagColor, supportsOpacity: false)
                } footer: {
                    if tag.isProtected {
                        Text("The \"favorite\" tag cannot be renamed or deleted.")
                    }
                }

                if showDuplicateError {
                    Section {
                        Text("A tag with this name already exists.")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    HStack {
                        Text("Used in")
                        Spacer()
                        Text("\(appState.tagUsageCount(tag)) recordings")
                            .foregroundColor(.secondary)
                    }
                }

                if !tag.isProtected {
                    Section {
                        Button(role: .destructive) {
                            deleteTag()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Tag")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveTag()
                    }
                    .disabled(!tag.isProtected && tagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Cannot Delete", isPresented: $showDeleteProtectedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The \"favorite\" tag is protected and cannot be deleted.")
            }
        }
    }

    private func saveTag() {
        let trimmedName = tagName.trimmingCharacters(in: .whitespaces)
        if appState.updateTag(tag, name: trimmedName, colorHex: tagColor.toHex()) {
            dismiss()
        } else {
            showDuplicateError = true
        }
    }

    private func deleteTag() {
        if tag.isProtected {
            showDeleteProtectedAlert = true
        } else if appState.deleteTag(tag) {
            dismiss()
        }
    }
}

// MARK: - Merge Tags Sheet

struct MergeTagsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let selectedTagIDs: Set<UUID>
    let onComplete: () -> Void

    @State private var destinationTagID: UUID?

    private var selectedTags: [Tag] {
        selectedTagIDs.compactMap { appState.tag(for: $0) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select the tag to keep. All selected tags will be merged into this one.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                List {
                    ForEach(selectedTags) { tag in
                        Button {
                            destinationTagID = tag.id
                        } label: {
                            HStack {
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 20, height: 20)

                                Text(tag.name)
                                    .foregroundColor(.primary)

                                Spacer()

                                if destinationTagID == tag.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .padding(.top)
            .navigationTitle("Merge Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Merge") {
                        mergeTags()
                    }
                    .disabled(destinationTagID == nil)
                }
            }
        }
    }

    private func mergeTags() {
        guard let destID = destinationTagID else { return }
        appState.mergeTags(sourceTagIDs: selectedTagIDs, destinationTagID: destID)
        dismiss()
        onComplete()
    }
}
