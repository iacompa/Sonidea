//
//  ProofManager.swift
//  Sonidea
//
//  CloudKit-based proof receipt manager.
//  Handles creating tamper-evident timestamps with offline queue support.
//
//  IMPORTANT: All CloudKit operations are BEST-EFFORT and never crash.
//  Recordings must open/play regardless of CloudKit availability.
//

import Foundation
import CloudKit
import Network
import OSLog

// MARK: - Proof Manager

@MainActor
@Observable
final class ProofManager {

    // MARK: - Properties

    /// Whether a proof operation is in progress
    var isProcessing = false

    /// Last error message (cleared on successful operation)
    var lastError: String?

    /// Whether CloudKit is available and properly configured
    private(set) var cloudKitAvailability: CloudKitAvailability = .unknown

    /// Pending queue for offline proofs
    private(set) var pendingQueue: [PendingProofItem] = []

    /// Guards against concurrent processPendingQueue() invocations during rapid network flaps
    private var isProcessingQueue = false

    /// Network path monitor for connectivity
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true

    /// Logger for diagnostics
    private let logger = Logger(subsystem: "com.iacompa.sonidea", category: "ProofManager")

    /// CloudKit container - lazily initialized only when safe
    private var _container: CKContainer?

    /// CloudKit container identifier (explicit, not default)
    /// This should match the container in your entitlements
    private static let containerIdentifier = "iCloud.com.iacompa.sonidea"

    /// Record type for proof receipts
    private static let recordType = "ProofReceipt"

    /// Pending queue file URL
    private var pendingQueueURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return documentsPath.appendingPathComponent("pending_proofs.json")
    }

    // MARK: - CloudKit Availability

    /// Detailed CloudKit availability status
    enum CloudKitAvailability: Equatable {
        case unknown
        case available
        case notSignedIn
        case restricted
        case noAccount
        case couldNotDetermine
        case unavailable(reason: String)

        var isAvailable: Bool {
            self == .available
        }

        var displayMessage: String {
            switch self {
            case .unknown:
                return "Checking iCloud status..."
            case .available:
                return "iCloud verification available"
            case .notSignedIn:
                return "Sign in to iCloud in Settings to enable verification"
            case .restricted:
                return "iCloud is restricted on this device"
            case .noAccount:
                return "No iCloud account configured"
            case .couldNotDetermine:
                return "Could not determine iCloud status"
            case .unavailable(let reason):
                return reason
            }
        }
    }

    // MARK: - Initialization

    init() {
        loadPendingQueue()
        startNetworkMonitoring()
        // Don't check CloudKit availability on init - do it lazily when needed
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Safe Container Access

    /// Safely get the CloudKit container, or nil if unavailable
    /// This NEVER calls CKContainer.default() - always uses explicit identifier
    /// Uses defensive checks to prevent EXC_BREAKPOINT crashes
    private func getContainerSafely() -> CKContainer? {
        // Return cached container if we have one
        if let container = _container {
            return container
        }

        // DEFENSIVE CHECK 1: Verify iCloud is available at all
        guard FileManager.default.ubiquityIdentityToken != nil else {
            logger.warning("iCloud not available - ubiquityIdentityToken is nil")
            cloudKitAvailability = .notSignedIn
            return nil
        }

        // DEFENSIVE CHECK 2: Verify the container identifier is valid
        // An empty or malformed identifier can cause crashes
        guard !Self.containerIdentifier.isEmpty,
              Self.containerIdentifier.hasPrefix("iCloud.") else {
            logger.error("Invalid container identifier: \(Self.containerIdentifier)")
            cloudKitAvailability = .unavailable(reason: "Invalid iCloud container configuration")
            return nil
        }

        // DEFENSIVE CHECK 3: Verify entitlements contain the container
        // Check if ubiquity container is accessible (this validates entitlements)
        let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier)
        if ubiquityURL == nil {
            // Container might not be in entitlements or not properly configured
            // Log warning but continue - CloudKit might still work for some operations
            logger.warning("Ubiquity container URL is nil - entitlements may be misconfigured")
        }

        // Use explicit container identifier - NEVER use CKContainer.default()
        // CKContainer.default() can SIGTRAP if entitlements are misconfigured
        let container = CKContainer(identifier: Self.containerIdentifier)
        _container = container

        logger.info("CloudKit container initialized: \(Self.containerIdentifier)")
        return container
    }

    /// Check CloudKit account status asynchronously
    /// Call this before attempting any CloudKit operations
    func checkCloudKitAvailability() async {
        guard let container = getContainerSafely() else {
            cloudKitAvailability = .notSignedIn
            return
        }

        do {
            let status = try await container.accountStatus()

            switch status {
            case .available:
                cloudKitAvailability = .available
                logger.info("CloudKit account available")
            case .noAccount:
                cloudKitAvailability = .noAccount
                logger.warning("No iCloud account")
            case .restricted:
                cloudKitAvailability = .restricted
                logger.warning("iCloud restricted")
            case .couldNotDetermine:
                cloudKitAvailability = .couldNotDetermine
                logger.warning("Could not determine iCloud status")
            case .temporarilyUnavailable:
                cloudKitAvailability = .unavailable(reason: "iCloud temporarily unavailable")
                logger.warning("iCloud temporarily unavailable")
            @unknown default:
                cloudKitAvailability = .unavailable(reason: "Unknown iCloud status")
                logger.warning("Unknown iCloud status")
            }
        } catch {
            cloudKitAvailability = .unavailable(reason: error.localizedDescription)
            logger.error("CloudKit account check failed: \(error.localizedDescription)")
        }
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
    /// This is BEST-EFFORT - failures are logged but never crash
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
        logger.info("Creating proof for recording: \(recording.id)")

        do {
            // Step 1: Compute SHA-256 hash of the audio file
            let sha256 = try await FileHasher.sha256Hash(of: recording.fileURL)
            logger.debug("Computed SHA-256: \(sha256.prefix(16))...")

            // Step 2: Compute location proof hash if location provided
            var locationProofHash: String? = nil
            if let payload = locationPayload, let jsonData = payload.canonicalJSON {
                locationProofHash = FileHasher.sha256Hash(of: jsonData)
            }

            // Step 3: Check CloudKit availability
            await checkCloudKitAvailability()

            guard cloudKitAvailability.isAvailable else {
                // CloudKit not available - set to pending or unavailable
                logger.warning("CloudKit not available: \(self.cloudKitAvailability.displayMessage)")

                if isNetworkAvailable {
                    // Online but CloudKit not available - mark as error
                    lastError = cloudKitAvailability.displayMessage
                    updatedRecording.proofStatusRaw = ProofStatus.error.rawValue
                } else {
                    // Offline - add to pending queue
                    addToPendingQueue(
                        recordingID: recording.id,
                        sha256: sha256,
                        locationPayload: locationPayload,
                        locationMode: locationMode
                    )
                    updatedRecording.proofStatusRaw = ProofStatus.pending.rawValue
                }

                updatedRecording.proofSHA256 = sha256
                updatedRecording.locationModeRaw = locationMode.rawValue
                updatedRecording.locationProofHash = locationProofHash
                setLocationProofStatus(&updatedRecording, locationProofHash: locationProofHash, status: .pending)

                isProcessing = false
                return updatedRecording
            }

            // Step 4: Try to upload to CloudKit
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
                    logger.info("Proof created successfully: \(recordName)")
                    updatedRecording.proofStatusRaw = ProofStatus.proven.rawValue
                    updatedRecording.proofSHA256 = sha256
                    updatedRecording.proofCloudCreatedAt = serverDate
                    updatedRecording.proofCloudRecordName = recordName
                    updatedRecording.locationModeRaw = locationMode.rawValue
                    updatedRecording.locationProofHash = locationProofHash
                    setLocationProofStatus(&updatedRecording, locationProofHash: locationProofHash, status: .verified)

                } catch {
                    // CloudKit error - add to pending queue
                    logger.error("CloudKit upload failed: \(error.localizedDescription)")
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
                    setLocationProofStatus(&updatedRecording, locationProofHash: locationProofHash, status: .pending)
                }
            } else {
                // Offline - add to pending queue
                logger.info("Offline - adding to pending queue")
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
                setLocationProofStatus(&updatedRecording, locationProofHash: locationProofHash, status: .pending)
            }

        } catch {
            logger.error("Proof creation failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
            updatedRecording.proofStatusRaw = ProofStatus.error.rawValue
        }

        isProcessing = false
        return updatedRecording
    }

    /// Helper to set location proof status
    private func setLocationProofStatus(_ recording: inout RecordingItem, locationProofHash: String?, status: LocationProofStatus) {
        if locationProofHash != nil {
            recording.locationProofStatusRaw = status.rawValue
        } else {
            recording.locationProofStatusRaw = LocationProofStatus.none.rawValue
        }
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
                logger.info("Proof verified - hash matches")
            } else {
                // Hash mismatch - file was modified
                logger.warning("Proof mismatch - file was modified")
                updatedRecording.proofStatusRaw = ProofStatus.mismatch.rawValue
            }

        } catch {
            logger.error("Proof verification failed: \(error.localizedDescription)")
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

        guard let container = getContainerSafely() else {
            throw ProofManagerError.cloudKitNotConfigured
        }

        let database = container.privateCloudDatabase

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
        // Don't add duplicates
        guard !pendingQueue.contains(where: { $0.recordingID == recordingID }) else {
            return
        }

        let item = PendingProofItem(
            recordingID: recordingID,
            sha256Hash: sha256,
            locationPayload: locationPayload,
            locationMode: locationMode
        )
        pendingQueue.append(item)
        savePendingQueue()
        logger.info("Added to pending queue: \(recordingID)")
    }

    /// Process the pending queue when network is available.
    /// Guarded by `isProcessingQueue` to prevent duplicate CK records
    /// when rapid network flaps trigger multiple concurrent invocations.
    func processPendingQueue() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        defer { isProcessingQueue = false }

        guard isNetworkAvailable else { return }
        guard !pendingQueue.isEmpty else { return }

        // Check CloudKit availability first
        await checkCloudKitAvailability()
        guard cloudKitAvailability.isAvailable else {
            logger.warning("Skipping pending queue - CloudKit unavailable")
            return
        }

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
                logger.info("Pending proof completed: \(item.recordingID)")

            } catch {
                // Increment retry count
                item.retryCount += 1
                item.lastRetryAt = Date()
                logger.warning("Pending proof retry \(item.retryCount) failed: \(error.localizedDescription)")

                if item.shouldRetry {
                    updatedQueue.append(item)
                } else {
                    logger.error("Pending proof dropped after max retries: \(item.recordingID)")
                }
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
            logger.info("Loaded \(self.pendingQueue.count) pending proofs")
        } catch {
            logger.error("Failed to load pending proof queue: \(error.localizedDescription)")
        }
    }

    private func savePendingQueue() {
        do {
            let data = try JSONEncoder().encode(pendingQueue)
            try data.write(to: pendingQueueURL, options: [.atomic, .completeFileProtection])
        } catch {
            logger.error("Failed to save pending proof queue: \(error.localizedDescription)")
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
            return "iCloud verification is not available. Please sign in to iCloud in Settings."
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let proofItemsCompleted = Notification.Name("proofItemsCompleted")
}
