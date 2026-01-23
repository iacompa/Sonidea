//
//  Album.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import Foundation

struct Album: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    var isSystem: Bool

    // System albums cannot be deleted
    var canDelete: Bool {
        !isSystem
    }

    // System albums cannot be renamed
    var canRename: Bool {
        !isSystem
    }

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), isSystem: Bool = false) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.isSystem = isSystem
    }

    // Well-known system album IDs
    static let draftsID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static let drafts = Album(
        id: draftsID,
        name: "Drafts",
        createdAt: Date(timeIntervalSince1970: 0),
        isSystem: true
    )
}
