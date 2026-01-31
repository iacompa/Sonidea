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
            #if DEBUG
            print("PhoneConnectivity: Failed to send theme: \(error)")
            #endif
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            #if DEBUG
            print("PhoneConnectivity: Activation error: \(error)")
            #endif
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
            #if DEBUG
            print("PhoneConnectivity: Received file without metadata")
            #endif
            return
        }

        guard let uuidString = metadata["uuid"] as? String else {
            #if DEBUG
            print("PhoneConnectivity: Missing uuid in metadata")
            #endif
            return
        }

        let duration = metadata["duration"] as? TimeInterval ?? 0
        let title = metadata["title"] as? String ?? "Watch Recording"
        let createdAt: Date = {
            if let timestamp = metadata["createdAt"] as? TimeInterval {
                return Date(timeIntervalSince1970: timestamp)
            }
            return Date()
        }()

        // Copy file synchronously to a stable location BEFORE dispatching to main.
        // WCSession may delete the file at file.fileURL after this delegate returns,
        // so we must preserve it before the async block runs.
        let stableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + file.fileURL.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: file.fileURL, to: stableURL)
        } catch {
            #if DEBUG
            print("PhoneConnectivity: Failed to copy received file to stable location: \(error)")
            #endif
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let appState = self.appState else {
                // Cleanup stable copy if we can't proceed
                try? FileManager.default.removeItem(at: stableURL)
                return
            }

            // Dedup check on main thread to prevent race conditions
            // when multiple files arrive simultaneously
            var importedUUIDs = UserDefaults.standard.stringArray(forKey: self.importedUUIDsKey) ?? []
            if importedUUIDs.contains(uuidString) {
                #if DEBUG
                print("PhoneConnectivity: Duplicate recording \(uuidString), skipping")
                #endif
                try? FileManager.default.removeItem(at: stableURL)
                return
            }

            // Check Pro + watch sync setting
            guard appState.supportManager.canUseProFeatures,
                  appState.appSettings.watchSyncEnabled else {
                #if DEBUG
                print("PhoneConnectivity: Watch sync requires Pro plan and Watch Sync enabled in settings")
                #endif
                try? FileManager.default.removeItem(at: stableURL)
                return
            }

            // Ensure the Watch Recordings album exists
            appState.ensureWatchRecordingsAlbum()

            // Import the recording into Watch Recordings album
            do {
                try appState.importRecording(
                    from: stableURL,
                    duration: duration,
                    title: title,
                    albumID: Album.watchRecordingsID,
                    createdAt: createdAt
                )

                // Mark as imported
                importedUUIDs.append(uuidString)
                // Trim to last 500 entries to prevent unbounded growth
                if importedUUIDs.count > 500 {
                    importedUUIDs = Array(importedUUIDs.suffix(500))
                }
                UserDefaults.standard.set(importedUUIDs, forKey: self.importedUUIDsKey)

                #if DEBUG
                print("PhoneConnectivity: Imported watch recording '\(title)'")
                #endif
            } catch {
                #if DEBUG
                print("PhoneConnectivity: Failed to import recording: \(error)")
                #endif
            }

            // Clean up the stable copy (importRecording copies into its own location)
            try? FileManager.default.removeItem(at: stableURL)
        }
    }
}
