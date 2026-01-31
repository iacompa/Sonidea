//
//  MixSettings.swift
//  Sonidea
//
//  Per-channel mix settings for overdub groups: volume, pan, mute, solo.
//

import Foundation

struct ChannelMixSettings: Codable, Equatable {
    var volume: Float = 1.0   // 0...1.5
    var pan: Float = 0.0      // -1 (L) ... +1 (R)
    var isMuted: Bool = false
    var isSolo: Bool = false
    var isLooped: Bool = false // When true, track repeats to fill total mix duration

    static let `default` = ChannelMixSettings()

    // Custom decoder for backward compatibility — older data lacks isLooped
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1.0
        pan = try container.decodeIfPresent(Float.self, forKey: .pan) ?? 0.0
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isSolo = try container.decodeIfPresent(Bool.self, forKey: .isSolo) ?? false
        isLooped = try container.decodeIfPresent(Bool.self, forKey: .isLooped) ?? false
    }

    init(volume: Float = 1.0, pan: Float = 0.0, isMuted: Bool = false, isSolo: Bool = false, isLooped: Bool = false) {
        self.volume = volume
        self.pan = pan
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.isLooped = isLooped
    }
}

struct MixSettings: Codable, Equatable {
    var baseChannel: ChannelMixSettings = .default
    var layerChannels: [ChannelMixSettings] = []
    var masterVolume: Float = 1.0

    /// Ensure layerChannels count matches actual layer count.
    mutating func syncLayerCount(_ count: Int) {
        while layerChannels.count < count {
            layerChannels.append(.default)
        }
        if layerChannels.count > count {
            layerChannels = Array(layerChannels.prefix(count))
        }
    }

    /// Compute effective volumes accounting for solo logic.
    /// When any channel is soloed, all non-solo channels get volume 0.
    func effectiveVolumes() -> (base: Float, layers: [Float]) {
        let anySolo = baseChannel.isSolo || layerChannels.contains { $0.isSolo }

        let baseVol: Float
        if baseChannel.isMuted {
            baseVol = 0
        } else if anySolo && !baseChannel.isSolo {
            baseVol = 0
        } else {
            baseVol = baseChannel.volume
        }

        let layerVols = layerChannels.map { ch -> Float in
            if ch.isMuted { return 0 }
            if anySolo && !ch.isSolo { return 0 }
            return ch.volume
        }

        return (base: baseVol * masterVolume, layers: layerVols.map { $0 * masterVolume })
    }
}
