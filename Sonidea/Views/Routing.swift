//
//  Routing.swift
//  Sonidea
//

import SwiftUI

// MARK: - Route Enum
enum AppRoute: String, CaseIterable {
    case recordings
    case map
}

// MARK: - Search Scope Enum
enum SearchScope: String, CaseIterable {
    case recordings
    case projects
    case albums

    var displayName: String {
        switch self {
        case .recordings: return "Recordings"
        case .projects: return "Projects"
        case .albums: return "Albums"
        }
    }
}

// MARK: - Search Mode Enum
enum SearchMode: String, CaseIterable {
    case `default`
    case calendar
    case timeline

    var iconName: String {
        switch self {
        case .default: return "magnifyingglass"
        case .calendar: return "calendar"
        case .timeline: return "clock"
        }
    }
}
