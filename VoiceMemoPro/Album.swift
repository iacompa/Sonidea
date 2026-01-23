//
//  Album.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import Foundation

struct Album: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
