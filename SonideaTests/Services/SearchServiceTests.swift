//
//  SearchServiceTests.swift
//  SonideaTests
//
//  Tests for SearchService: pure search functions.
//

import Testing
import Foundation
@testable import Sonidea

struct SearchServiceTests {

    // MARK: - Recording Search

    @Test func searchByTitle() {
        let recordings = [
            TestFixtures.makeRecording(title: "Morning Melody"),
            TestFixtures.makeRecording(title: "Evening Beat"),
            TestFixtures.makeRecording(title: "Lunch Idea")
        ]

        let results = SearchService.searchRecordings(
            query: "melody",
            recordings: recordings,
            tags: [],
            albums: [],
            projects: []
        )

        #expect(results.count == 1)
        #expect(results[0].title == "Morning Melody")
    }

    @Test func searchByTranscript() {
        let recordings = [
            TestFixtures.makeRecording(title: "Rec 1", transcript: "hello world"),
            TestFixtures.makeRecording(title: "Rec 2", transcript: "goodbye moon")
        ]

        let results = SearchService.searchRecordings(
            query: "hello",
            recordings: recordings,
            tags: [],
            albums: [],
            projects: []
        )

        #expect(results.count == 1)
        #expect(results[0].title == "Rec 1")
    }

    @Test func searchByNotes() {
        let recordings = [
            TestFixtures.makeRecording(title: "Rec", notes: "great bass line")
        ]

        let results = SearchService.searchRecordings(
            query: "bass",
            recordings: recordings,
            tags: [],
            albums: [],
            projects: []
        )

        #expect(results.count == 1)
    }

    @Test func searchByLocationLabel() {
        let recordings = [
            TestFixtures.makeRecording(title: "Rec", locationLabel: "Home Studio")
        ]

        let results = SearchService.searchRecordings(
            query: "studio",
            recordings: recordings,
            tags: [],
            albums: [],
            projects: []
        )

        #expect(results.count == 1)
    }

    @Test func searchCaseInsensitive() {
        let recordings = [
            TestFixtures.makeRecording(title: "UPPERCASE TITLE")
        ]

        let results = SearchService.searchRecordings(
            query: "uppercase",
            recordings: recordings,
            tags: [],
            albums: [],
            projects: []
        )

        #expect(results.count == 1)
    }

    @Test func searchEmptyQueryReturnsAll() {
        let recordings = [
            TestFixtures.makeRecording(title: "One"),
            TestFixtures.makeRecording(title: "Two")
        ]

        let results = SearchService.searchRecordings(
            query: "",
            recordings: recordings,
            tags: [],
            albums: [],
            projects: []
        )

        #expect(results.count == 2)
    }

    @Test func searchNoMatch() {
        let recordings = [
            TestFixtures.makeRecording(title: "Something")
        ]

        let results = SearchService.searchRecordings(
            query: "xyznonexistent",
            recordings: recordings,
            tags: [],
            albums: [],
            projects: []
        )

        #expect(results.isEmpty)
    }

    // MARK: - Tag Filtering

    @Test func filterByTag() {
        let tagID = UUID()
        let recordings = [
            TestFixtures.makeRecording(title: "Tagged", tagIDs: [tagID]),
            TestFixtures.makeRecording(title: "Untagged", tagIDs: [])
        ]

        let results = SearchService.searchRecordings(
            query: "",
            filterTagIDs: [tagID],
            recordings: recordings,
            tags: [],
            albums: [],
            projects: []
        )

        #expect(results.count == 1)
        #expect(results[0].title == "Tagged")
    }

    @Test func filterByTagAndQuery() {
        let tagID = UUID()
        let recordings = [
            TestFixtures.makeRecording(title: "Tagged Match", tagIDs: [tagID]),
            TestFixtures.makeRecording(title: "Tagged Other", tagIDs: [tagID]),
            TestFixtures.makeRecording(title: "Untagged Match", tagIDs: [])
        ]

        let results = SearchService.searchRecordings(
            query: "match",
            filterTagIDs: [tagID],
            recordings: recordings,
            tags: [],
            albums: [],
            projects: []
        )

        #expect(results.count == 1)
        #expect(results[0].title == "Tagged Match")
    }

    // MARK: - Tag Name Matching

    @Test func searchByTagName() {
        let tagID = UUID()
        let tag = Tag(id: tagID, name: "beatbox", colorHex: "#4ECDC4")

        let recordings = [
            TestFixtures.makeRecording(title: "Rec", tagIDs: [tagID])
        ]

        let results = SearchService.searchRecordings(
            query: "beatbox",
            recordings: recordings,
            tags: [tag],
            albums: [],
            projects: []
        )

        #expect(results.count == 1)
    }

    // MARK: - Album Name Matching

    @Test func searchByAlbumName() {
        let albumID = UUID()
        let album = TestFixtures.makeAlbum(id: albumID, name: "My Demos")

        let recordings = [
            TestFixtures.makeRecording(title: "Rec", albumID: albumID)
        ]

        let results = SearchService.searchRecordings(
            query: "demos",
            recordings: recordings,
            tags: [],
            albums: [album],
            projects: []
        )

        #expect(results.count == 1)
    }

    // MARK: - Project Title Matching

    @Test func searchByProjectTitle() {
        let projectID = UUID()
        let project = TestFixtures.makeProject(id: projectID, title: "Song Alpha")

        let recordings = [
            TestFixtures.makeRecording(title: "Rec", projectId: projectID)
        ]

        let results = SearchService.searchRecordings(
            query: "alpha",
            recordings: recordings,
            tags: [],
            albums: [],
            projects: [project]
        )

        #expect(results.count == 1)
    }

    // MARK: - Album Search

    @Test func searchAlbumsByName() {
        let albums = [
            TestFixtures.makeAlbum(name: "Demos"),
            TestFixtures.makeAlbum(name: "Finals"),
            TestFixtures.makeAlbum(name: "Demo Tracks")
        ]

        let results = SearchService.searchAlbums(query: "demo", albums: albums)
        #expect(results.count == 2)
    }

    @Test func searchAlbumsEmptyQuery() {
        let albums = [
            TestFixtures.makeAlbum(name: "One"),
            TestFixtures.makeAlbum(name: "Two")
        ]

        let results = SearchService.searchAlbums(query: "", albums: albums)
        #expect(results.count == 2)
    }

    // MARK: - Project Search

    @Test func searchProjectsByTitle() {
        let projects = [
            TestFixtures.makeProject(title: "Song Alpha"),
            TestFixtures.makeProject(title: "Beat Beta")
        ]

        let results = SearchService.searchProjects(query: "alpha", projects: projects)
        #expect(results.count == 1)
        #expect(results[0].title == "Song Alpha")
    }

    @Test func searchProjectsByNotes() {
        let projects = [
            TestFixtures.makeProject(title: "Song", notes: "needs more bass")
        ]

        let results = SearchService.searchProjects(query: "bass", projects: projects)
        #expect(results.count == 1)
    }

    @Test func searchProjectsEmptyQuery() {
        let projects = [
            TestFixtures.makeProject(title: "One"),
            TestFixtures.makeProject(title: "Two")
        ]

        let results = SearchService.searchProjects(query: "", projects: projects)
        #expect(results.count == 2)
    }
}
