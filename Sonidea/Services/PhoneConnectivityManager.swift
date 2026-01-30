//
//  PhoneConnectivityManager.swift
//  Sonidea
//
//  iOS-side WCSession manager for receiving watch recordings and syncing theme.
//

import WatchConnectivity
import Foundation

class PhoneConnectivityManager: NSObject, WCSessionDelegate {

    static let shared = PhoneConnectivityManager()

    weak var appState: AppState?

    private let importedUUIDsKey = "watchImportedUUIDs"

    private override init() {
        super.init()
    }

    // MARK: - Activate

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Send Theme

    func sendThemeToWatch(_ theme: AppTheme) {
        guard WCSession.default.activationState == .activated else { return }
        do {
            try WCSession.default.updateApplicationContext(["theme": theme.rawValue])
        } catch {
            print("PhoneConnectivity: Failed to send theme: \(error)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("PhoneConnectivity: Activation error: \(error)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // No-op
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate for Apple Watch pairing changes
        WCSession.default.activate()
    }

    // MARK: - Receive File Transfer from Watch

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let metadata = file.metadata else {
            print("PhoneConnectivity: Received file without metadata")
            return
        }

        guard let uuidString = metadata["uuid"] as? String else {
            print("PhoneConnectivity: Missing uuid in metadata")
            return
        }

        let duration = metadata["duration"] as? TimeInterval ?? 0
        let title = metadata["title"] as? String ?? "Watch Recording"

        DispatchQueue.main.async { [weak self] in
            guard let self, let appState = self.appState else { return }

            // Dedup check on main thread to prevent race conditions
            // when multiple files arrive simultaneously
            var importedUUIDs = UserDefaults.standard.stringArray(forKey: self.importedUUIDsKey) ?? []
            if importedUUIDs.contains(uuidString) {
                print("PhoneConnectivity: Duplicate recording \(uuidString), skipping")
                return
            }

            // Check Pro + watch sync setting
            guard appState.supportManager.canUseProFeatures,
                  appState.appSettings.watchSyncEnabled else {
                print("PhoneConnectivity: Watch sync requires Pro plan and Watch Sync enabled in settings")
                return
            }

            // Ensure the Watch Recordings album exists
            appState.ensureWatchRecordingsAlbum()

            // Import the recording into Watch Recordings album
            do {
                try appState.importRecording(
                    from: file.fileURL,
                    duration: duration,
                    title: title,
                    albumID: Album.watchRecordingsID
                )

                // Mark as imported
                importedUUIDs.append(uuidString)
                UserDefaults.standard.set(importedUUIDs, forKey: self.importedUUIDsKey)

                print("PhoneConnectivity: Imported watch recording '\(title)'")
            } catch {
                print("PhoneConnectivity: Failed to import recording: \(error)")
            }
        }
    }
}
