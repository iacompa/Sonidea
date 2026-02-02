//
//  WatchConnectivityService.swift
//  SonideaWatch Watch App
//
//  Watch-side WCSession for transferring recordings to iPhone and receiving theme updates.
//

import WatchConnectivity
import Foundation

// MARK: - Pending Transfer

struct PendingTransfer: Codable, Identifiable {
    let id: UUID            // Same as the recording UUID
    let fileName: String    // Filename of the recording
    let title: String
    let duration: TimeInterval
    let createdAt: Date
    let queuedAt: Date

    init(recording: WatchRecordingItem) {
        self.id = recording.id
        self.fileName = recording.fileName
        self.title = recording.title
        self.duration = recording.duration
        self.createdAt = recording.createdAt
        self.queuedAt = Date()
    }
}

class WatchConnectivityService: NSObject, WCSessionDelegate {

    static let shared = WatchConnectivityService()

    var onThemeUpdate: ((String) -> Void)?
    var onTransferConfirmed: ((UUID) -> Void)?

    private let pendingTransfersKey = "pendingTransfers"

    private override init() {
        super.init()
    }

    // MARK: - Activate

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Pending Transfers

    func savePendingTransfers(_ transfers: [PendingTransfer]) {
        guard let data = try? JSONEncoder().encode(transfers) else { return }
        UserDefaults.standard.set(data, forKey: pendingTransfersKey)
    }

    func loadPendingTransfers() -> [PendingTransfer] {
        guard let data = UserDefaults.standard.data(forKey: pendingTransfersKey),
              let transfers = try? JSONDecoder().decode([PendingTransfer].self, from: data) else {
            return []
        }
        return transfers
    }

    func addPendingTransfer(for recording: WatchRecordingItem) {
        var pending = loadPendingTransfers()
        // Don't add duplicates
        guard !pending.contains(where: { $0.id == recording.id }) else { return }
        pending.append(PendingTransfer(recording: recording))
        savePendingTransfers(pending)
    }

    func removePendingTransfer(id: UUID) {
        var pending = loadPendingTransfers()
        pending.removeAll { $0.id == id }
        savePendingTransfers(pending)
    }

    var pendingTransferCount: Int {
        loadPendingTransfers().count
    }

    // MARK: - Transfer Recording

    func transferRecording(_ recording: WatchRecordingItem) {
        // Save to pending queue before attempting transfer
        addPendingTransfer(for: recording)

        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else {
            #if DEBUG
            print("WatchConnectivity: Session not activated or phone not reachable, queued for retry")
            #endif
            return
        }

        performTransfer(recording)
    }

    private func performTransfer(_ recording: WatchRecordingItem) {
        let metadata: [String: Any] = [
            "uuid": recording.id.uuidString,
            "createdAt": recording.createdAt.timeIntervalSince1970,
            "title": recording.title,
            "duration": recording.duration
        ]

        WCSession.default.transferFile(recording.fileURL, metadata: metadata)
    }

    /// Retry all pending transfers when phone becomes reachable
    func retryPendingTransfers(recordings: [WatchRecordingItem]) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }

        let pending = loadPendingTransfers()
        for transfer in pending {
            if let recording = recordings.first(where: { $0.id == transfer.id }) {
                performTransfer(recording)
            }
        }
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

        // Check for transfer confirmations
        checkForConfirmations(in: session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let themeRaw = applicationContext["theme"] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.onThemeUpdate?(themeRaw)
            }
        }
        checkForConfirmations(in: applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        // Phone sends confirmation of successful import
        if let confirmedUUID = userInfo["transferConfirmed"] as? String,
           let uuid = UUID(uuidString: confirmedUUID) {
            removePendingTransfer(id: uuid)
            DispatchQueue.main.async { [weak self] in
                self?.onTransferConfirmed?(uuid)
            }
        }
    }

    private func checkForConfirmations(in context: [String: Any]) {
        if let confirmedUUIDs = context["confirmedTransfers"] as? [String] {
            for uuidString in confirmedUUIDs {
                if let uuid = UUID(uuidString: uuidString) {
                    removePendingTransfer(id: uuid)
                    DispatchQueue.main.async { [weak self] in
                        self?.onTransferConfirmed?(uuid)
                    }
                }
            }
        }
    }
}
