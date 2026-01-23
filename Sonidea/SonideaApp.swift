//
//  SonideaApp.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

@main
struct SonideaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
                .onAppear {
                    // Check for pending actions on app launch
                    appState.consumePendingStartRecording()
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        // Check for pending actions when app becomes active
                        appState.consumePendingStartRecording()
                    }
                }
                .onOpenURL { url in
                    // Handle deep links if needed
                    handleDeepLink(url)
                }
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
    }

    private func handleDeepLink(_ url: URL) {
        // Handle sonidea://record URL scheme
        if DeepLinks.isRecordURL(url) {
            AppState.setPendingStartRecording()
            appState.consumePendingStartRecording()
        }
    }
}

// MARK: - Quick Action Handler

/// Handles Home Screen Quick Actions (3D Touch / Long Press)
enum QuickActionHandler {
    static func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        switch shortcutItem.type {
        case "com.sonidea.newrecording":
            AppState.setPendingStartRecording()
            return true
        default:
            return false
        }
    }
}

// MARK: - App Delegate for Quick Actions

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Handle quick action if app was launched from it
        if let shortcutItem = options.shortcutItem {
            _ = QuickActionHandler.handleShortcutItem(shortcutItem)
        }

        let configuration = UISceneConfiguration(
            name: connectingSceneSession.configuration.name,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let handled = QuickActionHandler.handleShortcutItem(shortcutItem)
        completionHandler(handled)
    }
}
