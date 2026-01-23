//
//  VoiceMemoProApp.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

@main
struct VoiceMemoProApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
    }
}
