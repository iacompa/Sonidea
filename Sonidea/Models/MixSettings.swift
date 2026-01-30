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

    static let `default` = ChannelMixSettings()
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
