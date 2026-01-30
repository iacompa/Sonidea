//
//  MixdownEngine.swift
//  Sonidea
//
//  Offline mixdown engine for overdub groups.
//  Uses AVAudioEngine in manual rendering mode (.offline)
//  for faster-than-real-time bounce to a stereo WAV file.
//

import AVFoundation
import Foundation

struct MixdownResult {
    let outputURL: URL
    let duration: TimeInterval
    let success: Bool
    let error: Error?
}

@MainActor
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
            let baseFormat = baseFile.processingFormat
            let sampleRate = baseFormat.sampleRate

            let layerFiles = try layerFileURLs.map { try AVAudioFile(forReading: $0) }

            // Compute total duration (max of base + any offset layer)
            var maxFrames = baseFile.length
            for (i, file) in layerFiles.enumerated() {
                let offset = i < layerOffsets.count ? layerOffsets[i] : 0
                let endFrame = AVAudioFramePosition(offset * sampleRate) + file.length
                maxFrames = max(maxFrames, endFrame)
            }

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
            let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: baseFormat.channelCount, interleaved: false)!
            guard let baseBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: chunkSize) else {
                throw NSError(domain: "MixdownEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create base buffer"])
            }
            let layerBuffers = layerFiles.map { file -> AVAudioPCMBuffer? in
                let fmt = file.processingFormat
                return AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: chunkSize)
            }

            var position: AVAudioFramePosition = 0

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
                if position < baseFile.length {
                    let baseFrames = min(framesToProcess, AVAudioFrameCount(baseFile.length - position))
                    baseFile.framePosition = position
                    baseBuffer.frameLength = baseFrames
                    try baseFile.read(into: baseBuffer, frameCount: baseFrames)

                    if let baseData = baseBuffer.floatChannelData {
                        let vol = volumes.base
                        let pan = mixSettings.baseChannel.pan
                        let leftGain = vol * (1.0 - max(0, pan))
                        let rightGain = vol * (1.0 + min(0, pan))

                        for i in 0..<Int(baseFrames) {
                            let sample = baseData[0][i]
                            outLeft[i] += sample * leftGain
                            outRight[i] += sample * rightGain
                        }
                    }
                }

                // Mix each layer
                for (layerIdx, layerFile) in layerFiles.enumerated() {
                    let offset = layerIdx < layerOffsets.count ? layerOffsets[layerIdx] : 0
                    let offsetFrames = AVAudioFramePosition(offset * sampleRate)
                    let layerStart = position - offsetFrames

                    guard layerStart >= 0, layerStart < layerFile.length,
                          let layerBuf = layerBuffers[layerIdx] else { continue }

                    let layerFrames = min(framesToProcess, AVAudioFrameCount(layerFile.length - layerStart))
                    layerFile.framePosition = layerStart
                    layerBuf.frameLength = layerFrames
                    try layerFile.read(into: layerBuf, frameCount: layerFrames)

                    if let layerData = layerBuf.floatChannelData {
                        let vol = layerIdx < volumes.layers.count ? volumes.layers[layerIdx] : 1.0
                        let pan = layerIdx < mixSettings.layerChannels.count ? mixSettings.layerChannels[layerIdx].pan : 0.0
                        let leftGain = vol * (1.0 - max(0, pan))
                        let rightGain = vol * (1.0 + min(0, pan))

                        for i in 0..<Int(layerFrames) {
                            let sample = layerData[0][i]
                            outLeft[i] += sample * leftGain
                            outRight[i] += sample * rightGain
                        }
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
