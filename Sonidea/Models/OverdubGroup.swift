//
//  OverdubGroup.swift
//  Sonidea
//
//  Created by Claude on 1/25/26.
//

import Foundation

/// Represents an overdub group containing a base track and up to 3 layers
struct OverdubGroup: Identifiable, Codable, Equatable {
    let id: UUID
    let baseRecordingId: UUID
    var layerRecordingIds: [UUID]  // Ordered list of layer IDs
    let createdAt: Date
    var mixSettings: MixSettings = MixSettings()

    /// Maximum allowed layers per overdub group
    static let maxLayers = 3

    /// Number of layers currently recorded
    var layerCount: Int {
        layerRecordingIds.count
    }

    /// Whether more layers can be added
    var canAddLayer: Bool {
        layerCount < Self.maxLayers
    }

    /// All recording IDs in this group (base + layers)
    var allRecordingIds: [UUID] {
        [baseRecordingId] + layerRecordingIds
    }

    /// Next layer index (1, 2, or 3)
    var nextLayerIndex: Int? {
        guard canAddLayer else { return nil }
        return layerCount + 1
    }

    init(
        id: UUID = UUID(),
        baseRecordingId: UUID,
        layerRecordingIds: [UUID] = [],
        createdAt: Date = Date(),
        mixSettings: MixSettings = MixSettings()
    ) {
        self.id = id
        self.baseRecordingId = baseRecordingId
        self.layerRecordingIds = layerRecordingIds
        self.createdAt = createdAt
        self.mixSettings = mixSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        baseRecordingId = try container.decode(UUID.self, forKey: .baseRecordingId)
        layerRecordingIds = try container.decode([UUID].self, forKey: .layerRecordingIds)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        mixSettings = try container.decodeIfPresent(MixSettings.self, forKey: .mixSettings) ?? MixSettings()
    }

    /// Add a layer to the group
    mutating func addLayer(recordingId: UUID) -> Bool {
        guard canAddLayer else { return false }
        layerRecordingIds.append(recordingId)
        return true
    }

    /// Remove a layer from the group
    mutating func removeLayer(recordingId: UUID) {
        layerRecordingIds.removeAll { $0 == recordingId }
    }
}
