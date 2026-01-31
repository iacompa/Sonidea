//
//  WatchConnectivityService.swift
//  SonideaWatch Watch App
//
//  Watch-side WCSession for transferring recordings to iPhone and receiving theme updates.
//

import WatchConnectivity
import Foundation

class WatchConnectivityService: NSObject, WCSessionDelegate {

    static let shared = WatchConnectivityService()

    var onThemeUpdate: ((String) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Activate

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Transfer Recording

    func transferRecording(_ recording: WatchRecordingItem) {
        guard WCSession.default.activationState == .activated else {
            #if DEBUG
            print("WatchConnectivity: Session not activated, skipping transfer")
            #endif
            return
        }

        let metadata: [String: Any] = [
            "uuid": recording.id.uuidString,
            "createdAt": recording.createdAt.timeIntervalSince1970,
            "title": recording.title,
            "duration": recording.duration
        ]

        WCSession.default.transferFile(recording.fileURL, metadata: metadata)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            #if DEBUG
            print("WatchConnectivity: Activation error: \(error)")
            #endif
        }

        // Check for any pending theme from applicationContext
        if let themeRaw = session.receivedApplicationContext["theme"] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.onThemeUpdate?(themeRaw)
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let themeRaw = applicationContext["theme"] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.onThemeUpdate?(themeRaw)
            }
        }
    }
}
