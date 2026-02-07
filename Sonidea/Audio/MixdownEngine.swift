//
//  MixdownEngine.swift
//  Sonidea
//
//  Offline mixdown engine for overdub groups.
//  Uses AVAudioEngine in manual rendering mode (.offline)
//  for faster-than-real-time bounce to a stereo WAV file.
//

import Accelerate
import AVFoundation
import Foundation

struct MixdownResult {
    let outputURL: URL
    let duration: TimeInterval
    let success: Bool
    let error: Error?
}

final class MixdownEngine {

    /// Bounce an overdub group to a stereo WAV file.
    /// - Parameters:
    ///   - baseFileURL: File URL of the base recording
    ///   - layerFileURLs: File URLs of each layer
    ///   - layerOffsets: Start time offset (in seconds) for each layer relative to the base
    ///   - mixSettings: Volume/pan/mute/solo settings per channel
    ///   - outputURL: Destination file URL for the bounced WAV
    /// - Returns: MixdownResult with output URL and status
    func bounce(
        baseFileURL: URL,
        layerFileURLs: [URL],
        layerOffsets: [TimeInterval],
        mixSettings: MixSettings,
        outputURL: URL
    ) async -> MixdownResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performBounce(
                    baseFileURL: baseFileURL,
                    layerFileURLs: layerFileURLs,
                    layerOffsets: layerOffsets,
                    mixSettings: mixSettings,
                    outputURL: outputURL
                )
                continuation.resume(returning: result)
            }
        }
    }

    private func performBounce(
        baseFileURL: URL,
        layerFileURLs: [URL],
        layerOffsets: [TimeInterval],
        mixSettings: MixSettings,
        outputURL: URL
    ) -> MixdownResult {
        do {
            // Open all source files
            let baseFile = try AVAudioFile(forReading: baseFileURL)

            // Check disk space before bounce
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSize = attrs[.systemFreeSize] as? Int64, freeSize < 50_000_000 {
                return MixdownResult(outputURL: outputURL, duration: 0, success: false,
                    error: NSError(domain: "MixdownEngine", code: 10,
                        userInfo: [NSLocalizedDescriptionKey: "Not enough storage space to bounce. Please free up at least 50MB."]))
            }

            let baseFormat = baseFile.processingFormat
            let sampleRate = baseFormat.sampleRate

            let layerFiles = try layerFileURLs.map { try AVAudioFile(forReading: $0) }

            // Build sample rate converters for layers whose rate differs from the base
            let layerConverters: [AVAudioConverter?] = layerFiles.map { file in
                let layerRate = file.processingFormat.sampleRate
                guard layerRate != sampleRate else { return nil }
                guard let targetFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: sampleRate,
                    channels: file.processingFormat.channelCount,
                    interleaved: false
                ) else { return nil }
                return AVAudioConverter(from: file.processingFormat, to: targetFormat)
            }

            // Loop flags from mix settings
            let baseIsLooped = mixSettings.baseChannel.isLooped
            let layerLoopFlags: [Bool] = (0..<layerFiles.count).map { i in
                i < mixSettings.layerChannels.count && mixSettings.layerChannels[i].isLooped
            }

            // Compute total duration — non-looped tracks define the mix length.
            // Looped tracks repeat to fill that length.
            var maxNonLoopedFrames: AVAudioFramePosition = 0
            if !baseIsLooped {
                maxNonLoopedFrames = max(maxNonLoopedFrames, baseFile.length)
            }
            for (i, file) in layerFiles.enumerated() {
                if !layerLoopFlags[i] {
                    let offset = i < layerOffsets.count ? layerOffsets[i] : 0
                    let layerRate = file.processingFormat.sampleRate
                    let layerLengthInBaseFrames = AVAudioFramePosition(Double(file.length) * sampleRate / layerRate)
                    let endFrame = AVAudioFramePosition(offset * sampleRate) + layerLengthInBaseFrames
                    maxNonLoopedFrames = max(maxNonLoopedFrames, endFrame)
                }
            }

            // If ALL tracks are looped, use one full cycle of the longest track
            if maxNonLoopedFrames == 0 {
                maxNonLoopedFrames = baseFile.length
                for file in layerFiles {
                    let layerRate = file.processingFormat.sampleRate
                    let layerLengthInBaseFrames = AVAudioFramePosition(Double(file.length) * sampleRate / layerRate)
                    maxNonLoopedFrames = max(maxNonLoopedFrames, layerLengthInBaseFrames)
                }
            }

            let maxFrames = maxNonLoopedFrames

            // Create stereo output format
            guard let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: false
            ) else {
                throw NSError(domain: "MixdownEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create output format"])
            }

            // Effective volumes (handles solo/mute logic)
            let volumes = mixSettings.effectiveVolumes()

            // Create output file (16-bit WAV)
            let wavSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            try? FileManager.default.removeItem(at: outputURL)
            let outFile = try AVAudioFile(
                forWriting: outputURL,
                settings: wavSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )

            // Process in chunks
            let chunkSize: AVAudioFrameCount = 4096
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: chunkSize) else {
                throw NSError(domain: "MixdownEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
            }

            // Read buffers for each source
            guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: baseFormat.channelCount, interleaved: false) else {
                throw NSError(domain: "MixdownEngine", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format (sampleRate: \(sampleRate), channels: \(baseFormat.channelCount))"])
            }
            guard let baseBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: chunkSize) else {
                throw NSError(domain: "MixdownEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create base buffer"])
            }
            let layerBuffers = layerFiles.map { file -> AVAudioPCMBuffer? in
                let fmt = file.processingFormat
                return AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: chunkSize)
            }
            // Pre-allocate converted buffers for layers that need sample rate conversion
            let layerConvertedBuffers: [AVAudioPCMBuffer?] = layerConverters.map { converter in
                guard let converter = converter else { return nil }
                return AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: chunkSize)
            }

            var position: AVAudioFramePosition = 0

            // Pre-compute pan gains (constant across all chunks)
            let baseVol = volumes.base
            let basePan = mixSettings.baseChannel.pan
            let basePanAngle = (basePan + 1.0) / 2.0 * (.pi / 2.0)
            let baseLeftGain = baseVol * cos(basePanAngle)
            let baseRightGain = baseVol * sin(basePanAngle)

            struct LayerGains {
                let leftGain: Float
                let rightGain: Float
            }
            let layerGains: [LayerGains] = (0..<layerFiles.count).map { layerIdx in
                let vol = layerIdx < volumes.layers.count ? volumes.layers[layerIdx] : 1.0
                let pan = layerIdx < mixSettings.layerChannels.count ? mixSettings.layerChannels[layerIdx].pan : 0.0
                let panAngle = (pan + 1.0) / 2.0 * (.pi / 2.0)
                return LayerGains(leftGain: vol * cos(panAngle), rightGain: vol * sin(panAngle))
            }

            while position < maxFrames {
                let framesToProcess = min(chunkSize, AVAudioFrameCount(maxFrames - position))
                outBuffer.frameLength = framesToProcess

                guard let outLeft = outBuffer.floatChannelData?[0],
                      let outRight = outBuffer.floatChannelData?[1] else { break }

                // Zero output
                for i in 0..<Int(framesToProcess) {
                    outLeft[i] = 0
                    outRight[i] = 0
                }

                // Mix base track
                let baseLength = baseFile.length
                if baseIsLooped || position < baseLength {

                    // Fast path: non-looped base track can read sequentially without inner loop
                    if !baseIsLooped {
                        let readable = Int(min(AVAudioFramePosition(framesToProcess), baseLength - position))
                        if readable > 0 {
                            baseBuffer.frameLength = AVAudioFrameCount(readable)
                            try baseFile.read(into: baseBuffer, frameCount: AVAudioFrameCount(readable))

                            if let baseData = baseBuffer.floatChannelData {
                                let baseChans = Int(baseBuffer.format.channelCount)
                                var lGain = baseLeftGain
                                var rGain = baseRightGain
                                if baseChans >= 2 {
                                    // Stereo: left channel -> left output, right channel -> right output
                                    vDSP_vsma(baseData[0], 1, &lGain, outLeft, 1, outLeft, 1, vDSP_Length(readable))
                                    vDSP_vsma(baseData[1], 1, &rGain, outRight, 1, outRight, 1, vDSP_Length(readable))
                                } else {
                                    // Mono: same channel to both outputs with pan gains
                                    vDSP_vsma(baseData[0], 1, &lGain, outLeft, 1, outLeft, 1, vDSP_Length(readable))
                                    vDSP_vsma(baseData[0], 1, &rGain, outRight, 1, outRight, 1, vDSP_Length(readable))
                                }
                            }
                        }
                    } else {
                        // Looped path: inner loop handles wrap-around at track boundaries
                        var outOffset = 0
                        var remaining = Int(framesToProcess)
                        while remaining > 0 {
                            let globalPos = position + AVAudioFramePosition(outOffset)
                            let effectivePos = globalPos % baseLength

                            let framesUntilEnd = Int(baseLength - effectivePos)
                            let readable = min(remaining, framesUntilEnd)
                            guard readable > 0 else { break }

                            baseFile.framePosition = effectivePos
                            baseBuffer.frameLength = AVAudioFrameCount(readable)
                            try baseFile.read(into: baseBuffer, frameCount: AVAudioFrameCount(readable))

                            if let baseData = baseBuffer.floatChannelData {
                                let baseChans = Int(baseBuffer.format.channelCount)
                                var lGain = baseLeftGain
                                var rGain = baseRightGain
                                if baseChans >= 2 {
                                    // Stereo: left channel -> left output, right channel -> right output
                                    vDSP_vsma(baseData[0], 1, &lGain, outLeft + outOffset, 1, outLeft + outOffset, 1, vDSP_Length(readable))
                                    vDSP_vsma(baseData[1], 1, &rGain, outRight + outOffset, 1, outRight + outOffset, 1, vDSP_Length(readable))
                                } else {
                                    // Mono: same channel to both outputs with pan gains
                                    vDSP_vsma(baseData[0], 1, &lGain, outLeft + outOffset, 1, outLeft + outOffset, 1, vDSP_Length(readable))
                                    vDSP_vsma(baseData[0], 1, &rGain, outRight + outOffset, 1, outRight + outOffset, 1, vDSP_Length(readable))
                                }
                            }
                            outOffset += readable
                            remaining -= readable
                        }
                    }
                }

                // Mix each layer (with loop support and sample rate conversion)
                for (layerIdx, layerFile) in layerFiles.enumerated() {
                    let offset = layerIdx < layerOffsets.count ? layerOffsets[layerIdx] : 0
                    let offsetFrames = AVAudioFramePosition(offset * sampleRate)
                    let isLooped = layerLoopFlags[layerIdx]
                    let layerLength = layerFile.length
                    let layerRate = layerFile.processingFormat.sampleRate
                    let rateRatio = layerRate / sampleRate // layer-rate frames per base-rate frame
                    let needsConversion = layerConverters[layerIdx] != nil

                    guard let layerBuf = layerBuffers[layerIdx] else { continue }

                    let leftGain = layerGains[layerIdx].leftGain
                    let rightGain = layerGains[layerIdx].rightGain

                    var outOffset = 0
                    var remaining = Int(framesToProcess)
                    while remaining > 0 {
                        let globalPos = position + AVAudioFramePosition(outOffset)
                        let layerPos = globalPos - offsetFrames  // position in base-rate frames
                        guard layerPos >= 0 else {
                            // Haven't reached this layer's start yet — skip ahead
                            let framesToSkip = min(remaining, Int(-layerPos))
                            outOffset += framesToSkip
                            remaining -= framesToSkip
                            continue
                        }

                        // Convert position to layer-rate frames for file seeking
                        let layerPosNative = AVAudioFramePosition(Double(layerPos) * rateRatio)
                        let effectivePos = isLooped ? (layerPosNative % layerLength) : layerPosNative
                        if !isLooped && effectivePos >= layerLength { break }

                        let framesUntilEnd = Int(layerLength - effectivePos)
                        // How many layer-rate frames to read for 'remaining' base-rate output frames
                        let layerFramesNeeded = Int(ceil(Double(remaining) * rateRatio))
                        let readable = min(layerFramesNeeded, framesUntilEnd)
                        guard readable > 0 else { break }

                        layerFile.framePosition = effectivePos
                        layerBuf.frameLength = AVAudioFrameCount(readable)
                        try layerFile.read(into: layerBuf, frameCount: AVAudioFrameCount(readable))

                        // Determine the buffer to mix from (converted or raw)
                        let mixBuffer: AVAudioPCMBuffer
                        if needsConversion, let converter = layerConverters[layerIdx],
                           let convertedBuf = layerConvertedBuffers[layerIdx] {
                            // Convert from layer sample rate to base sample rate
                            convertedBuf.frameLength = 0
                            var error: NSError?
                            var allConsumed = false
                            converter.reset()
                            let status = converter.convert(to: convertedBuf, error: &error) { _, outStatus in
                                if allConsumed {
                                    outStatus.pointee = .noDataNow
                                    return nil
                                }
                                allConsumed = true
                                outStatus.pointee = .haveData
                                return layerBuf
                            }
                            guard status != .error else {
                                // Skip this chunk on conversion error
                                let outputFrames = max(1, Int(Double(readable) / rateRatio))
                                outOffset += outputFrames
                                remaining -= outputFrames
                                continue
                            }
                            mixBuffer = convertedBuf
                        } else {
                            mixBuffer = layerBuf
                        }

                        let mixFrames = Int(mixBuffer.frameLength)
                        let framesToMix = min(mixFrames, remaining)
                        guard framesToMix > 0 else { break }

                        if let layerData = mixBuffer.floatChannelData {
                            let layerChans = Int(mixBuffer.format.channelCount)
                            var lGain = leftGain
                            var rGain = rightGain
                            if layerChans >= 2 {
                                // Stereo: left channel -> left output, right channel -> right output
                                vDSP_vsma(layerData[0], 1, &lGain, outLeft + outOffset, 1, outLeft + outOffset, 1, vDSP_Length(framesToMix))
                                vDSP_vsma(layerData[1], 1, &rGain, outRight + outOffset, 1, outRight + outOffset, 1, vDSP_Length(framesToMix))
                            } else {
                                // Mono: same channel to both outputs with pan gains
                                vDSP_vsma(layerData[0], 1, &lGain, outLeft + outOffset, 1, outLeft + outOffset, 1, vDSP_Length(framesToMix))
                                vDSP_vsma(layerData[0], 1, &rGain, outRight + outOffset, 1, outRight + outOffset, 1, vDSP_Length(framesToMix))
                            }
                        }
                        outOffset += framesToMix
                        remaining -= framesToMix
                    }
                }

                // Write chunk
                try outFile.write(from: outBuffer)
                position += AVAudioFramePosition(framesToProcess)
            }

            let duration = Double(maxFrames) / sampleRate
            return MixdownResult(outputURL: outputURL, duration: duration, success: true, error: nil)
        } catch {
            return MixdownResult(outputURL: outputURL, duration: 0, success: false, error: error)
        }
    }
}
