//
//  DeepLinksTests.swift
//  SonideaTests
//
//  Tests for DeepLinks: URL scheme detection and parsing.
//

import Testing
import Foundation
@testable import Sonidea

struct DeepLinksTests {

    // MARK: - App Scheme

    @Test func appSchemeIsSonidea() {
        #expect(DeepLinks.appScheme == "sonidea")
    }

    // MARK: - Record URL Detection

    @Test func isRecordURLWithHostRecord() {
        let url = URL(string: "sonidea://record")!
        #expect(DeepLinks.isRecordURL(url))
    }

    @Test func isRecordURLWithPathRecord() {
        let url = URL(string: "sonidea:///record")!
        #expect(DeepLinks.isRecordURL(url))
    }

    @Test func isRecordURLRejectsWrongPath() {
        let url = URL(string: "sonidea://settings")!
        #expect(!DeepLinks.isRecordURL(url))
    }

    @Test func isRecordURLRejectsWrongScheme() {
        let url = URL(string: "https://record")!
        #expect(!DeepLinks.isRecordURL(url))
    }

    @Test func isRecordURLRejectsEmptyHost() {
        let url = URL(string: "sonidea://")!
        #expect(!DeepLinks.isRecordURL(url))
    }

    // MARK: - Record URL Construction

    @Test func recordURLIsValid() {
        let url = DeepLinks.recordURL
        #expect(url != nil)
        #expect(url?.scheme == "sonidea")
    }
}
