//
//  ProofManager.swift
//  Sonidea
//
//  CloudKit-based proof receipt manager.
//  Handles creating tamper-evident timestamps with offline queue support.
//

import Foundation
import CloudKit
import Network

// MARK: - Proof Manager

@MainActor
@Observable
final class ProofManager {

    // MARK: - Properties

    /// Whether a proof operation is in progress
    var isProcessing = false

    /// Last error message (cleared on successful operation)
    var lastError: String?

    /// Pending queue for offline proofs
    private(set) var pendingQueue: [PendingProofItem] = []

    /// Network path monitor for connectivity
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true

    /// CloudKit container (lazy to avoid crash if entitlements not configured)
    private var _container: CKContainer?
    private var container: CKContainer? {
        if _container == nil {
            // Check if CloudKit is available before accessing
            if isCloudKitAvailable {
                _container = CKContainer.default()
            }
        }
        return _container
    }
    private var privateDatabase: CKDatabase? { container?.privateCloudDatabase }

    /// Whether CloudKit is available (entitlements configured)
    var isCloudKitAvailable: Bool {
        // Check if iCloud is available on the device
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Record type for proof receipts
    private static let recordType = "ProofReceipt"

    /// Pending queue file URL
    private var pendingQueueURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("pending_proofs.json")
    }

    // MARK: - Initialization

    init() {
        loadPendingQueue()
        startNetworkMonitoring()
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasAvailable = self?.isNetworkAvailable ?? true
                self?.isNetworkAvailable = path.status == .satisfied

                // Retry pending queue when network becomes available
                if self?.isNetworkAvailable == true && !wasAvailable {
                    await self?.processPendingQueue()
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    // MARK: - Create Proof

    /// Create a proof receipt for a recording
    /// - Parameters:
    ///   - recording: The recording to create proof for
    ///   - locationPayload: Optional location data
    ///   - locationMode: The location capture mode used
    /// - Returns: Updated recording with proof fields set
    func createProof(
        for recording: RecordingItem,
        locationPayload: LocationPayload?,
        locationMode: LocationMode
    ) async -> RecordingItem {
        isProcessing = true
        lastError = nil

        var updatedRecording = recording

        do {
            // Step 1: Compute SHA-256 hash of the audio file
            let sha256 = try await FileHasher.sha256Hash(of: recording.fileURL)

            // Step 2: Compute location proof hash if location provided
            var locationProofHash: String? = nil
            if let payload = locationPayload, let jsonData = payload.canonicalJSON {
                locationProofHash = FileHasher.sha256Hash(of: jsonData)
            }

            // Step 3: Try to upload to CloudKit
            if isNetworkAvailable {
                do {
                    let (recordName, serverDate) = try await uploadToCloudKit(
                        recordingID: recording.id,
                        sha256: sha256,
                        locationPayload: locationPayload,
                        locationMode: locationMode,
                        locationProofHash: locationProofHash
                    )

                    // Success - update recording with proven status
                    updatedRecording.proofStatusRaw = ProofStatus.proven.rawValue
                    updatedRecording.proofSHA256 = sha256
                    updatedRecording.proofCloudCreatedAt = serverDate
                    updatedRecording.proofCloudRecordName = recordName
                    updatedRecording.locationModeRaw = locationMode.rawValue
                    updatedRecording.locationProofHash = locationProofHash

                } catch {
                    // CloudKit error - add to pending queue
                    lastError = error.localizedDescription
                    addToPendingQueue(
                        recordingID: recording.id,
                        sha256: sha256,
                        locationPayload: locationPayload,
                        locationMode: locationMode
                    )

                    updatedRecording.proofStatusRaw = ProofStatus.pending.rawValue
                    updatedRecording.proofSHA256 = sha256
                    updatedRecording.locationModeRaw = locationMode.rawValue
                    updatedRecording.locationProofHash = locationProofHash
                }
            } else {
                // Offline - add to pending queue
                addToPendingQueue(
                    recordingID: recording.id,
                    sha256: sha256,
                    locationPayload: locationPayload,
                    locationMode: locationMode
                )

                updatedRecording.proofStatusRaw = ProofStatus.pending.rawValue
                updatedRecording.proofSHA256 = sha256
                updatedRecording.locationModeRaw = locationMode.rawValue
                updatedRecording.locationProofHash = locationProofHash
            }

        } catch {
            lastError = error.localizedDescription
            updatedRecording.proofStatusRaw = ProofStatus.error.rawValue
        }

        isProcessing = false
        return updatedRecording
    }

    // MARK: - Verify Proof

    /// Verify a recording's proof by re-hashing the file
    /// - Parameter recording: The recording to verify
    /// - Returns: Updated recording with verification result
    func verifyProof(for recording: RecordingItem) async -> RecordingItem {
        guard let storedHash = recording.proofSHA256 else {
            return recording
        }

        isProcessing = true
        var updatedRecording = recording

        do {
            let currentHash = try await FileHasher.sha256Hash(of: recording.fileURL)

            if currentHash == storedHash {
                // Hash matches - file unchanged
                if recording.proofStatus == .proven {
                    // Already proven, nothing to update
                }
            } else {
                // Hash mismatch - file was modified
                updatedRecording.proofStatusRaw = ProofStatus.mismatch.rawValue
            }

        } catch {
            lastError = error.localizedDescription
            updatedRecording.proofStatusRaw = ProofStatus.error.rawValue
        }

        isProcessing = false
        return updatedRecording
    }

    // MARK: - CloudKit Operations

    private func uploadToCloudKit(
        recordingID: UUID,
        sha256: String,
        locationPayload: LocationPayload?,
        locationMode: LocationMode,
        locationProofHash: String?
    ) async throws -> (recordName: String, serverDate: Date) {

        guard let database = privateDatabase else {
            throw ProofManagerError.cloudKitNotConfigured
        }

        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)

        record["recordingID"] = recordingID.uuidString
        record["sha256Hash"] = sha256
        record["locationMode"] = locationMode.rawValue

        if let locationHash = locationProofHash {
            record["locationProofHash"] = locationHash
        }

        if let payload = locationPayload {
            record["latitude"] = payload.latitude
            record["longitude"] = payload.longitude
            if let accuracy = payload.horizontalAccuracy {
                record["horizontalAccuracy"] = accuracy
            }
            if let altitude = payload.altitude {
                record["altitude"] = altitude
            }
            record["locationTimestamp"] = payload.timestamp
            if let address = payload.manualAddress {
                record["manualAddress"] = address
            }
        }

        let savedRecord = try await database.save(record)

        guard let serverDate = savedRecord.creationDate else {
            throw ProofManagerError.noServerDate
        }

        return (savedRecord.recordID.recordName, serverDate)
    }

    // MARK: - Pending Queue

    private func addToPendingQueue(
        recordingID: UUID,
        sha256: String,
        locationPayload: LocationPayload?,
        locationMode: LocationMode
    ) {
        let item = PendingProofItem(
            recordingID: recordingID,
            sha256Hash: sha256,
            locationPayload: locationPayload,
            locationMode: locationMode
        )
        pendingQueue.append(item)
        savePendingQueue()
    }

    /// Process the pending queue when network is available
    func processPendingQueue() async {
        guard isNetworkAvailable else { return }
        guard !pendingQueue.isEmpty else { return }

        var updatedQueue: [PendingProofItem] = []
        var completedItems: [(UUID, String, Date)] = [] // (recordingID, recordName, serverDate)

        for var item in pendingQueue {
            do {
                var locationProofHash: String? = nil
                if let payload = item.locationPayload, let jsonData = payload.canonicalJSON {
                    locationProofHash = FileHasher.sha256Hash(of: jsonData)
                }

                let (recordName, serverDate) = try await uploadToCloudKit(
                    recordingID: item.recordingID,
                    sha256: item.sha256Hash,
                    locationPayload: item.locationPayload,
                    locationMode: item.locationMode,
                    locationProofHash: locationProofHash
                )

                completedItems.append((item.recordingID, recordName, serverDate))

            } catch {
                // Increment retry count
                item.retryCount += 1
                item.lastRetryAt = Date()

                if item.shouldRetry {
                    updatedQueue.append(item)
                }
                // If max retries reached, item is dropped
            }
        }

        pendingQueue = updatedQueue
        savePendingQueue()

        // Notify of completed items (caller should update recordings)
        if !completedItems.isEmpty {
            NotificationCenter.default.post(
                name: .proofItemsCompleted,
                object: completedItems
            )
        }
    }

    /// Remove a pending item for a specific recording
    func removePendingItem(for recordingID: UUID) {
        pendingQueue.removeAll { $0.recordingID == recordingID }
        savePendingQueue()
    }

    // MARK: - Persistence

    private func loadPendingQueue() {
        guard FileManager.default.fileExists(atPath: pendingQueueURL.path) else { return }

        do {
            let data = try Data(contentsOf: pendingQueueURL)
            pendingQueue = try JSONDecoder().decode([PendingProofItem].self, from: data)
        } catch {
            print("Failed to load pending proof queue: \(error)")
        }
    }

    private func savePendingQueue() {
        do {
            let data = try JSONEncoder().encode(pendingQueue)
            try data.write(to: pendingQueueURL)
        } catch {
            print("Failed to save pending proof queue: \(error)")
        }
    }
}

// MARK: - Proof Manager Error

enum ProofManagerError: LocalizedError {
    case noServerDate
    case networkUnavailable
    case cloudKitNotConfigured

    var errorDescription: String? {
        switch self {
        case .noServerDate:
            return "CloudKit did not return a server timestamp"
        case .networkUnavailable:
            return "Network unavailable"
        case .cloudKitNotConfigured:
            return "iCloud is not available. Sign in to iCloud in Settings."
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let proofItemsCompleted = Notification.Name("proofItemsCompleted")
}
