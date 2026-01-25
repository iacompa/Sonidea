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
            ThemedAppContainer(appState: appState)
                .onAppear {
                    // CRITICAL: Clean up any stuck Live Activities on app launch
                    // This prevents the Dynamic Island from showing when not recording
                    cleanupStaleActivities()

                    // Check for pending actions on app launch
                    appState.consumePendingStartRecording()
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        // Check for pending actions when app becomes active
                        appState.consumePendingStartRecording()

                        // Also check for pending stop request from Live Activity
                        if appState.recorder.consumePendingStopRequest() {
                            // User tapped stop in Live Activity while app was backgrounded
                            appState.recorder.onStopAndSaveRequested?()
                        }

                        // Clean up Live Activities if not recording
                        // This handles the case where app was killed while recording
                        cleanupStaleActivities()
                    } else if newPhase == .background {
                        // When going to background, verify Live Activity state matches recording state
                        if !appState.recorder.isActive {
                            RecordingLiveActivityManager.shared.endAllActivities()
                        }
                    }
                }
                .onOpenURL { url in
                    // Handle deep links if needed
                    handleDeepLink(url)
                }
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
    }

    /// Clean up any stale Live Activities that don't correspond to an active recording
    private func cleanupStaleActivities() {
        // If there's no active recording session, end all Live Activities
        let isRecording = appState.recorder.isActive
        RecordingLiveActivityManager.shared.cleanupIfNotRecording(isCurrentlyRecording: isRecording)
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

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Clean up any stuck Live Activities from previous app sessions
        // This runs before any UI appears
        Task { @MainActor in
            RecordingLiveActivityManager.shared.endAllActivities()
        }
        return true
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

// MARK: - Themed App Container

/// Container view that injects theme palette into the environment
struct ThemedAppContainer: View {
    @Bindable var appState: AppState
    @Environment(\.colorScheme) private var systemColorScheme

    private var effectiveColorScheme: ColorScheme {
        // Theme can force a color scheme, or follow system
        appState.selectedTheme.forcedColorScheme ?? appState.appearanceMode.preferredColorScheme ?? systemColorScheme
    }

    private var currentPalette: ThemePalette {
        appState.selectedTheme.palette(for: effectiveColorScheme)
    }

    var body: some View {
        ContentView()
            .environment(appState)
            .environment(\.themePalette, currentPalette)
            .environment(\.appTheme, appState.selectedTheme)
            .preferredColorScheme(appState.selectedTheme.forcedColorScheme ?? appState.appearanceMode.preferredColorScheme)
    }
}
