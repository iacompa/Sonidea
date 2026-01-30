//
//  AudioDebugTests.swift
//  SonideaTests
//
//  Tests for AudioFileStatus enum and AudioDebug helpers.
//

import Testing
import Foundation
@testable import Sonidea

struct AudioDebugTests {

    // MARK: - AudioFileStatus.isValid

    @Test func validStatusIsValid() {
        let status = AudioFileStatus.valid(duration: 5.0)
        #expect(status.isValid)
        #expect(status.errorMessage == nil)
    }

    @Test func notFoundStatusIsNotValid() {
        let status = AudioFileStatus.notFound
        #expect(!status.isValid)
        #expect(status.errorMessage != nil)
    }

    @Test func emptyStatusIsNotValid() {
        let status = AudioFileStatus.empty
        #expect(!status.isValid)
        #expect(status.errorMessage != nil)
    }

    @Test func tooSmallStatusIsNotValid() {
        let status = AudioFileStatus.tooSmall(50)
        #expect(!status.isValid)
        #expect(status.errorMessage?.contains("50") == true)
    }

    @Test func zeroDurationStatusIsNotValid() {
        let status = AudioFileStatus.zeroDuration
        #expect(!status.isValid)
        #expect(status.errorMessage != nil)
    }

    @Test func attributeErrorStatusIsNotValid() {
        let error = NSError(domain: "test", code: 1)
        let status = AudioFileStatus.attributeError(error)
        #expect(!status.isValid)
        #expect(status.errorMessage != nil)
    }

    @Test func audioErrorStatusIsNotValid() {
        let error = NSError(domain: "test", code: 2)
        let status = AudioFileStatus.audioError(error)
        #expect(!status.isValid)
        #expect(status.errorMessage != nil)
    }

    // MARK: - Verify Audio File

    @Test func verifyNonexistentFile() {
        let url = URL(fileURLWithPath: "/nonexistent/recording.m4a")
        let status = AudioDebug.verifyAudioFile(url: url)

        if case .notFound = status {
            // Expected
        } else {
            #expect(Bool(false), "Expected .notFound but got \(status)")
        }
    }

    // MARK: - PlaybackError

    @Test func playbackErrorDescriptions() {
        let url = URL(fileURLWithPath: "/test/file.m4a")

        let notFound = PlaybackError.fileNotFound(url)
        #expect(notFound.errorDescription?.contains("file.m4a") == true)

        let cantOpen = PlaybackError.cannotOpenFile(url, NSError(domain: "test", code: 1))
        #expect(cantOpen.errorDescription != nil)

        let sessionFailed = PlaybackError.audioSessionFailed(NSError(domain: "test", code: 2))
        #expect(sessionFailed.errorDescription != nil)

        let engineFailed = PlaybackError.engineStartFailed(NSError(domain: "test", code: 3))
        #expect(engineFailed.errorDescription != nil)
    }
}
