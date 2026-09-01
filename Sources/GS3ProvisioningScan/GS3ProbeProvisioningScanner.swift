// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

#if canImport(CoreBluetooth)
import Foundation
import GS3DeviceProvisioning
import SensorOwnership
@preconcurrency import CoreBluetooth

public enum GS3ProbeProvisioningScanError: Error, Sendable, Equatable {
    case alreadyRunning
    case ownershipUnavailable
    case bluetoothUnavailable
    case permissionDenied
    case canceled
}

extension GS3ProbeProvisioningScanError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "A scan-only provisioning operation is already running."
        case .ownershipUnavailable:
            "Another Sugarman process owns sensor access. Stop it before provisioning."
        case .bluetoothUnavailable:
            "Bluetooth is unavailable for scan-only provisioning."
        case .permissionDenied:
            "Bluetooth permission was denied for scan-only provisioning."
        case .canceled:
            "The scan-only provisioning operation was canceled."
        }
    }
}

public protocol GS3ProbeProvisioningScanning: Sendable {
    func scan(
        matching request: GS3ProbeBridgeScanRequest,
        timeoutSeconds: TimeInterval
    ) async throws -> UUID
    func cancel()
}

/// Bounded, scan-only CoreBluetooth adapter for resolving the host-local UUID
/// associated with an existing Probe document. It has no peripheral
/// connection, GATT discovery, subscription, authentication, history, command,
/// or write API. The shared local owner lease is retained until scanning ends.
public final class GS3ProbeProvisioningScanner:
    NSObject, GS3ProbeProvisioningScanning, @unchecked Sendable
{
    public static let scanWindowSeconds: TimeInterval = 10

    private let externalOwnershipGate: GS3ExternalOwnershipGate
    private let queue = DispatchQueue(label: "app.sugarman.provisioning-scan")
    private var central: CBCentralManager?
    private var continuation: CheckedContinuation<UUID, Error>?
    private var activeScanToken: UUID?
    private var accumulator: GS3ProbeBridgeDiscoveryAccumulator?
    private var timeoutWorkItem: DispatchWorkItem?
    private var ownerLease: SensorOwnerLease?

    public init(externalOwnershipGate: GS3ExternalOwnershipGate) {
        self.externalOwnershipGate = externalOwnershipGate
        super.init()
    }

    public func scan(
        matching request: GS3ProbeBridgeScanRequest,
        timeoutSeconds: TimeInterval = scanWindowSeconds
    ) async throws -> UUID {
        try externalOwnershipGate.requireConfirmation()
        try Task.checkCancellation()
        let scanToken = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.sync {
                    self.begin(
                        scanToken: scanToken,
                        request: request,
                        timeoutSeconds: timeoutSeconds,
                        continuation: continuation
                    )
                }
            }
        } onCancel: {
            cancel(scanToken: scanToken)
        }
    }

    public func cancel() {
        queue.async {
            self.finish(.failure(GS3ProbeProvisioningScanError.canceled))
        }
    }

    private func begin(
        scanToken: UUID,
        request: GS3ProbeBridgeScanRequest,
        timeoutSeconds: TimeInterval,
        continuation: CheckedContinuation<UUID, Error>
    ) {
        guard self.continuation == nil else {
            continuation.resume(throwing: GS3ProbeProvisioningScanError.alreadyRunning)
            return
        }
        guard timeoutSeconds > 0, timeoutSeconds.isFinite else {
            continuation.resume(throwing: GS3ProbeProvisioningScanError.bluetoothUnavailable)
            return
        }
        do {
            try externalOwnershipGate.requireConfirmation()
            ownerLease = try SharedSensorOwnerLease.acquire()
        } catch is GS3ExternalOwnershipError {
            continuation.resume(throwing: GS3ExternalOwnershipError.confirmationRequired)
            return
        } catch {
            continuation.resume(throwing: GS3ProbeProvisioningScanError.ownershipUnavailable)
            return
        }
        switch CBManager.authorization {
        case .denied, .restricted:
            ownerLease?.release()
            ownerLease = nil
            continuation.resume(throwing: GS3ProbeProvisioningScanError.permissionDenied)
            return
        case .allowedAlways, .notDetermined:
            break
        @unknown default:
            ownerLease?.release()
            ownerLease = nil
            continuation.resume(throwing: GS3ProbeProvisioningScanError.bluetoothUnavailable)
            return
        }

        self.continuation = continuation
        activeScanToken = scanToken
        accumulator = GS3ProbeBridgeDiscoveryAccumulator(request: request)
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.finishFromAccumulator()
        }
        self.timeoutWorkItem = timeoutWorkItem
        queue.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWorkItem)
        central = CBCentralManager(
            delegate: self,
            queue: queue,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    private func finishFromAccumulator() {
        guard let accumulator else {
            finish(.failure(GS3ProbeProvisioningScanError.bluetoothUnavailable))
            return
        }
        do {
            finish(.success(try accumulator.selectedPeripheralID()))
        } catch {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<UUID, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        activeScanToken = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        central?.stopScan()
        central?.delegate = nil
        central = nil
        accumulator = nil
        ownerLease?.release()
        ownerLease = nil
        continuation.resume(with: result)
    }

    private func cancel(scanToken: UUID) {
        queue.async {
            guard self.activeScanToken == scanToken else { return }
            self.finish(.failure(GS3ProbeProvisioningScanError.canceled))
        }
    }
}

extension GS3ProbeProvisioningScanner: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard continuation != nil else { return }
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        case .unauthorized:
            finish(.failure(GS3ProbeProvisioningScanError.permissionDenied))
        case .poweredOff, .unsupported, .resetting:
            finish(.failure(GS3ProbeProvisioningScanError.bluetoothUnavailable))
        case .unknown:
            break
        @unknown default:
            finish(.failure(GS3ProbeProvisioningScanError.bluetoothUnavailable))
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let localName = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        accumulator?.observe(
            peripheralID: peripheral.identifier,
            localName: localName
        )
    }
}
#endif
