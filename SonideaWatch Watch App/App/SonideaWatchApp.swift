//
//  SonideaWatchApp.swift
//  SonideaWatch Watch App
//
//  Entry point for the watchOS companion app.
//

import SwiftUI

@main
struct SonideaWatchApp: App {
    @State private var appState = WatchAppState()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(appState)
                .environment(\.watchPalette, appState.currentPalette)
                .onAppear {
                    // Wire theme updates from phone
                    WatchConnectivityService.shared.onThemeUpdate = { rawValue in
                        appState.applyTheme(rawValue)
                    }
                    WatchConnectivityService.shared.activate()
                }
        }
    }
}
