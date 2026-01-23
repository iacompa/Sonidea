//
//  ContentView.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Route Enum
enum AppRoute: String, CaseIterable {
    case recordings
    case map
}

// MARK: - Search Scope Enum
enum SearchScope: String, CaseIterable {
    case recordings
    case albums

    var displayName: String {
        switch self {
        case .recordings: return "Recordings"
        case .albums: return "Albums"
        }
    }
}

// MARK: - Record Button Position Manager

class RecordButtonPositionManager: ObservableObject {
    static let shared = RecordButtonPositionManager()

    private let posXKey = "recordButtonPosX"
    private let posYKey = "recordButtonPosY"
    private let hasStoredKey = "recordButtonHasStored"

    // Stored absolute position (center of button)
    @Published var storedX: CGFloat = 0
    @Published var storedY: CGFloat = 0
    @Published var hasStoredPosition: Bool = false

    init() {
        let defaults = UserDefaults.standard
        hasStoredPosition = defaults.bool(forKey: hasStoredKey)
        if hasStoredPosition {
            storedX = CGFloat(defaults.double(forKey: posXKey))
            storedY = CGFloat(defaults.double(forKey: posYKey))
        }
    }

    func save(x: CGFloat, y: CGFloat) {
        storedX = x
        storedY = y
        hasStoredPosition = true
        UserDefaults.standard.set(Double(x), forKey: posXKey)
        UserDefaults.standard.set(Double(y), forKey: posYKey)
        UserDefaults.standard.set(true, forKey: hasStoredKey)
    }

    /// Reset button to default position with animation support
    /// Pass defaultX/Y to animate smoothly to default; omit to just clear persistence
    func reset(toDefaultX: CGFloat? = nil, toDefaultY: CGFloat? = nil) {
        // If default coordinates provided, set stored position to animate there
        if let x = toDefaultX, let y = toDefaultY {
            storedX = x
            storedY = y
        }
        hasStoredPosition = false
        UserDefaults.standard.removeObject(forKey: posXKey)
        UserDefaults.standard.removeObject(forKey: posYKey)
        UserDefaults.standard.set(false, forKey: hasStoredKey)
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @Environment(AppState.self) var appState
    @State private var currentRoute: AppRoute = .recordings
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showTipJar = false

    // Record button position
    @StateObject private var buttonPosition = RecordButtonPositionManager.shared
    @GestureState private var dragTranslation: CGSize = .zero
    @State private var isDragging = false

    // Reset bubble state
    @State private var showResetBubble = false

    // Layout constants
    private let topBarHeight: CGFloat = 56
    private let buttonSize: CGFloat = 80
    private let edgePadding: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let safeArea = geometry.safeAreaInsets
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height + safeArea.top + safeArea.bottom

            // Default button position: bottom center, just above home indicator
            // This mimics Apple Voice Memos positioning
            let defaultX = geometry.size.width / 2
            let defaultY = geometry.size.height + safeArea.top - buttonSize / 2 - 16

            // Calculate bounds for button center
            // BOUNDS EXPLANATION:
            // - minY: Top menu bar is forbidden (safe area top + bar height + button radius + padding)
            // - maxY: Button can go all the way to bottom, just above home indicator area
            // - minX/maxX: Keep button fully on screen with edge padding
            let buttonRadius = buttonSize / 2
            let minX = edgePadding + buttonRadius
            let maxX = geometry.size.width - edgePadding - buttonRadius
            let minY = safeArea.top + topBarHeight + buttonRadius + 8
            let maxY = geometry.size.height + safeArea.top - safeArea.bottom - buttonRadius - 8

            // Determine current button position
            // Use stored position if we have one (or if storedX/Y were set for animation), otherwise use default
            let hasPosition = buttonPosition.hasStoredPosition || buttonPosition.storedX != 0 || buttonPosition.storedY != 0
            let baseX = hasPosition ? buttonPosition.storedX : defaultX
            let baseY = hasPosition ? buttonPosition.storedY : defaultY

            // Apply drag translation and clamp to bounds
            let buttonX = clamp(baseX + dragTranslation.width, min: minX, max: maxX)
            let buttonY = clamp(baseY + dragTranslation.height, min: minY, max: maxY)

            ZStack(alignment: .top) {
                // Layer 1: Main Content (fills screen)
                mainContentLayer(safeArea: safeArea)

                // Layer 2: Fixed Top Bar (always on top, never moves)
                fixedTopBar(safeArea: safeArea)

                // Layer 3: Floating Record Button + Reset Bubble (only on Recordings screen)
                if currentRoute == .recordings {
                    // Reset bubble (shown on long-press, positioned below button)
                    if showResetBubble {
                        resetBubbleOverlay(
                            buttonX: buttonX,
                            buttonY: buttonY,
                            defaultX: defaultX,
                            defaultY: defaultY,
                            screenHeight: geometry.size.height + safeArea.top
                        )
                        .zIndex(99)
                    }

                    // The record button
                    floatingRecordButton(
                        x: buttonX,
                        y: buttonY,
                        defaultX: defaultX,
                        defaultY: defaultY,
                        minX: minX, maxX: maxX,
                        minY: minY, maxY: maxY
                    )
                    .zIndex(100)
                }
            }
            .ignoresSafeArea()
            .coordinateSpace(name: "ContentView")
        }
        .sheet(isPresented: $showSearch) {
            SearchSheetView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView()
        }
        .sheet(isPresented: $showTipJar) {
            TipJarSheetView()
        }
        // Dismiss reset bubble when tapping outside
        .onTapGesture {
            if showResetBubble {
                withAnimation(.easeOut(duration: 0.15)) {
                    showResetBubble = false
                }
            }
        }
    }

    // MARK: - Main Content Layer

    @ViewBuilder
    private func mainContentLayer(safeArea: EdgeInsets) -> some View {
        switch currentRoute {
        case .recordings:
            Color(.systemBackground)
                .ignoresSafeArea()
                .overlay(
                    VStack(spacing: 0) {
                        // Space for fixed top bar
                        Color.clear
                            .frame(height: safeArea.top + topBarHeight)

                        // Recording HUD (when recording)
                        if appState.recorder.isRecording {
                            RecordingHUDCard(
                                duration: appState.recorder.currentDuration,
                                liveSamples: appState.recorder.liveMeterSamples
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Recordings list
                        RecordingsListView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                )

        case .map:
            // Full-screen map
            GPSInsightsMapView()
                .ignoresSafeArea()
        }
    }

    // MARK: - Fixed Top Bar

    private func fixedTopBar(safeArea: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            topNavigationBar
                .padding(.horizontal, 12)
                .padding(.top, safeArea.top + 8)
                .padding(.bottom, 8)
                .background(
                    Rectangle()
                        .fill(currentRoute == .map ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.systemBackground)))
                        .ignoresSafeArea(edges: .top)
                )

            Spacer()
        }
    }

    // MARK: - Floating Record Button

    private func floatingRecordButton(
        x: CGFloat, y: CGFloat,
        defaultX: CGFloat, defaultY: CGFloat,
        minX: CGFloat, maxX: CGFloat,
        minY: CGFloat, maxY: CGFloat
    ) -> some View {
        VoiceMemosRecordButton {
            // Only handle tap if not showing reset bubble
            if !showResetBubble {
                handleRecordTap()
            }
        }
        .frame(width: buttonSize, height: buttonSize)
        .contentShape(Circle())
        .position(x: x, y: y)
        .shadow(color: .black.opacity(isDragging ? 0.3 : 0.2), radius: isDragging ? 12 : 8, y: isDragging ? 6 : 4)
        .scaleEffect(isDragging ? 1.05 : 1.0)
        // Long-press gesture for reset bubble
        .onLongPressGesture(minimumDuration: 0.5) {
            // Show reset bubble with animation
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showResetBubble = true
            }
        }
        // Drag gesture for moving the button
        .highPriorityGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .named("ContentView"))
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation
                }
                .onChanged { _ in
                    // Dismiss reset bubble when starting drag
                    if showResetBubble {
                        withAnimation(.easeOut(duration: 0.1)) {
                            showResetBubble = false
                        }
                    }
                    if !isDragging {
                        isDragging = true
                    }
                }
                .onEnded { value in
                    isDragging = false

                    // Calculate final position from current base + translation
                    let currentBaseX: CGFloat
                    let currentBaseY: CGFloat
                    if buttonPosition.hasStoredPosition {
                        currentBaseX = buttonPosition.storedX
                        currentBaseY = buttonPosition.storedY
                    } else if buttonPosition.storedX != 0 || buttonPosition.storedY != 0 {
                        currentBaseX = buttonPosition.storedX
                        currentBaseY = buttonPosition.storedY
                    } else {
                        currentBaseX = defaultX
                        currentBaseY = defaultY
                    }

                    let finalX = clamp(currentBaseX + value.translation.width, min: minX, max: maxX)
                    let finalY = clamp(currentBaseY + value.translation.height, min: minY, max: maxY)

                    // Save with spring animation
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        buttonPosition.save(x: finalX, y: finalY)
                    }
                }
        )
        .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: isDragging)
    }

    // MARK: - Reset Bubble Overlay

    private func resetBubbleOverlay(
        buttonX: CGFloat,
        buttonY: CGFloat,
        defaultX: CGFloat,
        defaultY: CGFloat,
        screenHeight: CGFloat
    ) -> some View {
        // Position bubble below button, or above if too close to bottom
        let bubbleHeight: CGFloat = 44
        let bubbleSpacing: CGFloat = 12
        let buttonBottom = buttonY + buttonSize / 2
        let spaceBelow = screenHeight - buttonBottom
        let showAbove = spaceBelow < (bubbleHeight + bubbleSpacing + 20)

        let bubbleY: CGFloat
        if showAbove {
            bubbleY = buttonY - buttonSize / 2 - bubbleSpacing - bubbleHeight / 2
        } else {
            bubbleY = buttonY + buttonSize / 2 + bubbleSpacing + bubbleHeight / 2
        }

        return ResetBubble(showAbove: showAbove) {
            // Reset action
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                buttonPosition.reset(toDefaultX: defaultX, toDefaultY: defaultY)
                showResetBubble = false
            }
        }
        .position(x: buttonX, y: bubbleY)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    // MARK: - Helper Functions

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }

    // MARK: - Top Navigation Bar

    private var topNavigationBar: some View {
        HStack(spacing: 8) {
            // Left cluster: Settings, Map, Recordings
            HStack(spacing: 8) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentRoute = .map
                    }
                } label: {
                    Image(systemName: "map.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(currentRoute == .map ? .accentColor : .primary)
                        .frame(width: 44, height: 44)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentRoute = .recordings
                    }
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(currentRoute == .recordings ? .accentColor : .primary)
                        .frame(width: 44, height: 44)
                }
            }

            Spacer()

            // Right cluster: Search, Tip Jar
            HStack(spacing: 8) {
                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }

                Button {
                    showTipJar = true
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
            }
        }
    }

    // MARK: - Record Button Handler

    private func handleRecordTap() {
        if appState.recorder.isRecording {
            if let rawData = appState.recorder.stopRecording() {
                appState.addRecording(from: rawData)
                currentRoute = .recordings
            }
        } else {
            appState.recorder.startRecording()
        }
    }
}

// MARK: - Reset Bubble View

struct ResetBubble: View {
    let showAbove: Bool
    let onReset: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onReset) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                Text("Reset")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 8, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Voice Memos Style Record Button

struct VoiceMemosRecordButton: View {
    @Environment(AppState.self) var appState
    let action: () -> Void

    @State private var isPulsing = false

    private var isRecording: Bool {
        appState.recorder.isRecording
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(isRecording ? Color.red : Color.red.opacity(0.3), lineWidth: 4)
                    .frame(width: 80, height: 80)
                    .scaleEffect(isRecording && isPulsing ? 1.08 : 1.0)
                    .animation(
                        isRecording ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                        value: isPulsing
                    )

                // Inner fill
                Circle()
                    .fill(Color.red)
                    .frame(width: 68, height: 68)

                // Mic icon
                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: isRecording) { _, newValue in
            isPulsing = newValue
        }
        .onAppear {
            isPulsing = isRecording
        }
    }
}

// MARK: - Premium Recording HUD Card

struct RecordingHUDCard: View {
    let duration: TimeInterval
    let liveSamples: [Float]

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false

    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }

    private var currentInputName: String {
        AudioSessionManager.shared.currentInput?.portName ?? "Built-in Microphone"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top section: Recording indicator + Timer
            HStack(alignment: .center) {
                // Left: Pulsing dot + Recording label
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                            value: isPulsing
                        )
                        .shadow(color: .red.opacity(0.5), radius: isPulsing ? 6 : 2)

                    Text("Recording")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }

                Spacer()

                // Right: Large timer
                Text(formattedDuration)
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.red)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Middle: Waveform visualization
            ZStack {
                if liveSamples.isEmpty {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 56)
                } else {
                    LiveWaveformView(samples: liveSamples)
                        .frame(height: 56)
                }
            }
            .padding(.horizontal, 20)

            // Divider
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            // Bottom section: Input + Level meter
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(currentInputName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let lastSample = liveSamples.last {
                    PremiumLevelMeter(level: lastSample)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Premium Level Meter

struct PremiumLevelMeter: View {
    let level: Float

    private let barCount = 6
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let maxHeight: CGFloat = 16

    private func barHeight(at index: Int) -> CGFloat {
        let baseHeight: CGFloat = 4
        let increment = (maxHeight - baseHeight) / CGFloat(barCount - 1)
        return baseHeight + increment * CGFloat(index)
    }

    private func isActive(at index: Int) -> Bool {
        let threshold = Float(index) / Float(barCount)
        return level >= threshold
    }

    private func barColor(at index: Int) -> Color {
        guard isActive(at: index) else {
            return Color(.systemGray4)
        }
        if index >= barCount - 1 {
            return .red
        } else if index >= barCount - 2 {
            return .orange
        } else {
            return .green
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor(at: index))
                    .frame(width: barWidth, height: barHeight(at: index))
            }
        }
    }
}

// MARK: - Legacy Level Indicator (kept for compatibility)
struct LevelIndicator: View {
    let level: Float

    private var barCount: Int { 5 }

    private func barColor(at index: Int) -> Color {
        let threshold = Float(index) / Float(barCount)
        if level >= threshold {
            if index >= barCount - 1 {
                return .red
            } else if index >= barCount - 2 {
                return .orange
            } else {
                return .green
            }
        }
        return Color(.systemGray4)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(at: index))
                    .frame(width: 4, height: CGFloat(8 + index * 3))
            }
        }
    }
}

// MARK: - Placeholder Views
struct MapPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Map")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text("Recording locations will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Search Sheet View
struct SearchSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var searchScope: SearchScope = .recordings
    @State private var searchQuery = ""
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var selectedRecording: RecordingItem?
    @State private var selectedAlbum: Album?

    private var recordingResults: [RecordingItem] {
        appState.searchRecordings(query: searchQuery, filterTagIDs: selectedTagIDs)
    }

    private var albumResults: [Album] {
        appState.searchAlbums(query: searchQuery)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 16) {
                    Picker("Search Scope", selection: $searchScope) {
                        ForEach(SearchScope.allCases, id: \.self) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField(searchScope == .recordings ? "Search recordings..." : "Search albums...", text: $searchQuery)
                            .foregroundColor(.primary)
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)

                    if searchScope == .recordings && !appState.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(appState.tags) { tag in
                                    TagFilterChip(
                                        tag: tag,
                                        isSelected: selectedTagIDs.contains(tag.id)
                                    ) {
                                        if selectedTagIDs.contains(tag.id) {
                                            selectedTagIDs.remove(tag.id)
                                        } else {
                                            selectedTagIDs.insert(tag.id)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    if searchScope == .recordings {
                        recordingsResultsView
                    } else {
                        albumsResultsView
                    }
                }
                .padding(.top)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
            .sheet(item: $selectedAlbum) { album in
                AlbumDetailSheet(album: album)
            }
            .onChange(of: searchScope) { _, _ in
                if searchScope == .albums {
                    selectedTagIDs.removeAll()
                }
            }
        }
    }

    @ViewBuilder
    private var recordingsResultsView: some View {
        if recordingResults.isEmpty {
            Spacer()
            if searchQuery.isEmpty && selectedTagIDs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Search your recordings")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Search by title, notes, location, tags, or album")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No recordings found")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
            }
            Spacer()
        } else {
            List {
                ForEach(recordingResults) { recording in
                    SearchResultRow(recording: recording)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedRecording = recording
                        }
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var albumsResultsView: some View {
        if albumResults.isEmpty {
            Spacer()
            if searchQuery.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Search your albums")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Find albums by name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No albums found")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
            }
            Spacer()
        } else {
            List {
                ForEach(albumResults) { album in
                    AlbumSearchRow(album: album)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedAlbum = album
                        }
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Album Search Row

struct AlbumSearchRow: View {
    @Environment(AppState.self) var appState
    let album: Album

    private var recordingCount: Int {
        appState.recordingCount(in: album)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.fill")
                .font(.system(size: 20))
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray4))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(recordingCount) recording\(recordingCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Album Detail Sheet

struct AlbumDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let album: Album

    @State private var selectedTagIDs: Set<UUID> = []
    @State private var selectedRecording: RecordingItem?

    private var albumRecordings: [RecordingItem] {
        let recordings = appState.recordings(in: album)

        if selectedTagIDs.isEmpty {
            return recordings
        }

        return recordings.filter { recording in
            !selectedTagIDs.isDisjoint(with: Set(recording.tagIDs))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 16) {
                    if !appState.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(appState.tags) { tag in
                                    TagFilterChip(
                                        tag: tag,
                                        isSelected: selectedTagIDs.contains(tag.id)
                                    ) {
                                        if selectedTagIDs.contains(tag.id) {
                                            selectedTagIDs.remove(tag.id)
                                        } else {
                                            selectedTagIDs.insert(tag.id)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    if albumRecordings.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "waveform.circle")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            if selectedTagIDs.isEmpty {
                                Text("No recordings in this album")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            } else {
                                Text("No recordings match selected tags")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(albumRecordings) { recording in
                                SearchResultRow(recording: recording)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedRecording = recording
                                    }
                                    .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
                .padding(.top)
            }
            .navigationTitle(album.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
        }
    }
}

// MARK: - Tag Filter Chip

struct TagFilterChip: View {
    let tag: Tag
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tag.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : tag.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? tag.color : Color.clear)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(tag.color, lineWidth: 1)
                )
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    @Environment(AppState.self) var appState
    @Environment(\.colorScheme) var colorScheme
    let recording: RecordingItem

    private var recordingTags: [Tag] {
        appState.tags(for: recording.tagIDs)
    }

    private var album: Album? {
        appState.album(for: recording.albumID)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Use the same isolated icon tile component
            RecordingIconTile(recording: recording, colorScheme: colorScheme)

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(recording.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let album = album {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(album.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if !recordingTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(recordingTags.prefix(3)) { tag in
                            TagChipSmall(tag: tag)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Settings Sheet
struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var isExporting = false
    @State private var exportProgress: String = ""
    @State private var showShareSheet = false
    @State private var exportedZIPURL: URL?
    @State private var showAlbumPicker = false
    @State private var showTagManager = false
    @State private var showTrashView = false
    @State private var showEmptyTrashAlert = false
    @State private var showFileImporter = false

    @State private var showLockScreenHelp = false
    @State private var showActionButtonHelp = false
    @State private var showSiriShortcutsHelp = false

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            List {
                Section {
                    Button {
                        showLockScreenHelp = true
                    } label: {
                        HStack {
                            Image(systemName: "lock.rectangle.on.rectangle")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("Lock Screen Widget")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        showActionButtonHelp = true
                    } label: {
                        HStack {
                            Image(systemName: "button.horizontal.top.press")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("Action Button")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        showSiriShortcutsHelp = true
                    } label: {
                        HStack {
                            Image(systemName: "mic.badge.plus")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("Siri & Shortcuts")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Quick Access")
                } footer: {
                    Text("Set up fast ways to start recording from anywhere.")
                }

                Section {
                    Picker("Quality", selection: $appState.appSettings.recordingQuality) {
                        ForEach(RecordingQualityPreset.allCases) { preset in
                            VStack(alignment: .leading) {
                                Text(preset.displayName)
                            }
                            .tag(preset)
                        }
                    }
                } header: {
                    Text("Recording Quality")
                } footer: {
                    Text(appState.appSettings.recordingQuality.description)
                }

                Section {
                    HStack {
                        Text("Current Input")
                        Spacer()
                        Text(AudioSessionManager.shared.currentInput?.portName ?? "Default")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Audio Input")
                }

                Section {
                    Picker("Skip Interval", selection: $appState.appSettings.skipInterval) {
                        ForEach(SkipInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }

                    HStack {
                        Text("Playback Speed")
                        Spacer()
                        Text(String(format: "%.1fx", appState.appSettings.playbackSpeed))
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Playback")
                }

                Section {
                    Toggle("Auto-Transcribe", isOn: $appState.appSettings.autoTranscribe)

                    Picker("Language", selection: $appState.appSettings.transcriptionLanguage) {
                        ForEach(TranscriptionLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                } header: {
                    Text("Transcription")
                } footer: {
                    Text("Auto-transcribe new recordings when saved.")
                }

                Section {
                    Picker("Appearance", selection: $appState.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                }

                Section {
                    Button {
                        showTagManager = true
                    } label: {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundColor(.blue)
                            Text("Manage Tags")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(appState.tags.count)")
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Tags")
                }

                Section {
                    Button {
                        exportAllRecordings()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                            Text("Export All Recordings")
                                .foregroundColor(.primary)
                            Spacer()
                            if isExporting && exportProgress == "all" {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                        }
                    }
                    .disabled(isExporting || appState.activeRecordings.isEmpty)

                    Button {
                        showAlbumPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "square.stack")
                                .foregroundColor(.blue)
                            Text("Export Album...")
                                .foregroundColor(.primary)
                            Spacer()
                            if isExporting && exportProgress == "album" {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                        }
                    }
                    .disabled(isExporting || appState.albums.isEmpty)

                    Button {
                        showFileImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(.blue)
                            Text("Import Recordings")
                                .foregroundColor(.primary)
                        }
                    }
                } header: {
                    Text("Export & Import")
                } footer: {
                    Text("Export as WAV files in ZIP. Import m4a, wav, mp3, or aiff files.")
                }

                Section {
                    Button {
                        showTrashView = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("View Trash")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(appState.trashedCount) items")
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        showEmptyTrashAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.slash")
                            Text("Empty Trash Now")
                        }
                    }
                    .disabled(appState.trashedCount == 0)
                } header: {
                    Text("Trash")
                } footer: {
                    Text("Items in trash are automatically deleted after 30 days.")
                }

                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("VoiceMemoPro")
                        Spacer()
                        Text("1.0")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedZIPURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showAlbumPicker) {
                ExportAlbumPickerSheet { album in
                    exportAlbum(album)
                }
            }
            .sheet(isPresented: $showTagManager) {
                TagManagerView()
            }
            .sheet(isPresented: $showTrashView) {
                TrashView()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio, .mpeg4Audio, .wav, .mp3, .aiff],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
            .alert("Empty Trash?", isPresented: $showEmptyTrashAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Empty Trash", role: .destructive) {
                    appState.emptyTrash()
                }
            } message: {
                Text("This will permanently delete \(appState.trashedCount) items. This cannot be undone.")
            }
            .sheet(isPresented: $showLockScreenHelp) {
                LockScreenWidgetHelpSheet()
            }
            .sheet(isPresented: $showActionButtonHelp) {
                ActionButtonHelpSheet()
            }
            .sheet(isPresented: $showSiriShortcutsHelp) {
                SiriShortcutsHelpSheet()
            }
        }
    }

    private func exportAllRecordings() {
        isExporting = true
        exportProgress = "all"
        Task {
            do {
                let zipURL = try await AudioExporter.shared.exportRecordings(
                    appState.activeRecordings,
                    scope: .all,
                    albumLookup: { appState.album(for: $0) },
                    tagsLookup: { appState.tags(for: $0) }
                )
                exportedZIPURL = zipURL
                isExporting = false
                exportProgress = ""
                showShareSheet = true
            } catch {
                isExporting = false
                exportProgress = ""
            }
        }
    }

    private func exportAlbum(_ album: Album) {
        isExporting = true
        exportProgress = "album"
        Task {
            do {
                let recordings = appState.recordings(in: album)
                let zipURL = try await AudioExporter.shared.exportRecordings(
                    recordings,
                    scope: .album(album),
                    albumLookup: { appState.album(for: $0) },
                    tagsLookup: { appState.tags(for: $0) }
                )
                exportedZIPURL = zipURL
                isExporting = false
                exportProgress = ""
                showShareSheet = true
            } catch {
                isExporting = false
                exportProgress = ""
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                let duration = getAudioDuration(url: url)
                appState.importRecording(from: url, duration: duration)
            }
        case .failure(let error):
            print("Import failed: \(error)")
        }
    }

    private func getAudioDuration(url: URL) -> TimeInterval {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            return duration
        } catch {
            return 0
        }
    }
}

// MARK: - Trash View
struct TrashView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            Group {
                if appState.trashedRecordings.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "trash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Trash is Empty")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                } else {
                    List {
                        ForEach(appState.trashedRecordings) { recording in
                            TrashItemRow(recording: recording)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Trash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct TrashItemRow: View {
    @Environment(AppState.self) private var appState
    let recording: RecordingItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.body)
                    .fontWeight(.medium)

                if let days = recording.daysUntilPurge {
                    Text("Deletes in \(days) day\(days == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            Button {
                appState.restoreFromTrash(recording)
            } label: {
                Text("Restore")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            Button {
                appState.permanentlyDelete(recording)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Export Album Picker Sheet
struct ExportAlbumPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let onSelect: (Album) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.albums) { album in
                    Button {
                        dismiss()
                        onSelect(album)
                    } label: {
                        HStack {
                            Text(album.name)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(appState.recordingCount(in: album)) recordings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Select Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Tip Jar Sheet
struct TipJarSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.pink)
                    Text("Tip Jar")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("Support the developer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Tip Jar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environment(AppState())
}
