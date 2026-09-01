// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Protocol
import GS3Session
import SugarmanStore

#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth

/// Foreground-only V3 adapter for one already-known, already-active owned
/// sensor. It has no scan API, restoration identifier, activation, binding,
/// reset, unacknowledged write, or arbitrary-frame entry point.
package final class GS3ForegroundCoreBluetoothTransport:
    NSObject, GS3ForegroundTransporting, @unchecked Sendable, CustomReflectable
{
    private enum Phase: Equatable {
        case idle
        case waitingForPower
        case connecting
        case connected
        case discoveringService
        case serviceDiscovered
        case discoveringCharacteristics
        case characteristicsDiscovered
        case subscribing
        case subscribed
        case authenticating
        case authenticated
        case awaitingHistory
        case streaming
        case disconnecting
    }

    private enum InFlightCommand: Equatable {
        case authentication
        case effectiveData
    }

    package static let queueLabel = "app.sugarman.ios.gs3.foreground"
    package static let operationTimeoutSeconds: TimeInterval = 15
    package static let synchronizationTimeoutSeconds: TimeInterval = 120

    private static let serviceUUID = CBUUID(string: "FF30")
    private static let notificationUUID = CBUUID(string: "FF31")
    private static let transmissionUUID = CBUUID(string: "FF32")

    private let queue: DispatchQueue
    private let peripheralID: UUID
    private let material: V3ActiveSessionMaterial
    private let operationTimeout: TimeInterval
    private let synchronizationTimeout: TimeInterval
    private let receiptClock: @Sendable () -> Date

    private var eventHandler: (@Sendable (GS3ForegroundTransportEvent) -> Void)?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var service: CBService?
    private var notificationCharacteristic: CBCharacteristic?
    private var transmissionCharacteristic: CBCharacteristic?
    private var phase: Phase = .idle
    private var operationToken: UUID?
    private var responseToken: UUID?
    private var pendingDisconnectReason: GS3DisconnectReason?
    private var controlledDisconnect = false
    private var inFlightCommand: InFlightCommand?
    private var queuedHistoryPlan: HistoryRequestPlan?
    private var authenticationWriteCallCount = 0
    private var effectiveDataWriteCallCount = 0
    private var authenticationAccepted = false
    private var effectiveDataWriteAcknowledged = false
    private var historyControlAcknowledged = false
    private var historyReadyEmitted = false
    private var hasReceivedGlucoseBatch = false
    private var historyPreambleCount = 0
    private var protocolRejectionReported = false

    package init(
        peripheralID: UUID,
        material: V3ActiveSessionMaterial,
        operationTimeoutSeconds: TimeInterval = GS3ForegroundCoreBluetoothTransport
            .operationTimeoutSeconds,
        synchronizationTimeoutSeconds: TimeInterval = GS3ForegroundCoreBluetoothTransport
            .synchronizationTimeoutSeconds,
        receiptClock: @escaping @Sendable () -> Date = { Date() }
    ) {
        precondition(
            operationTimeoutSeconds.isFinite
                && operationTimeoutSeconds > 0
                && operationTimeoutSeconds <= 300
        )
        precondition(
            synchronizationTimeoutSeconds.isFinite
                && synchronizationTimeoutSeconds > 0
                && synchronizationTimeoutSeconds <= 300
        )
        self.peripheralID = peripheralID
        self.material = material
        self.queue = DispatchQueue(label: Self.queueLabel)
        self.operationTimeout = operationTimeoutSeconds
        self.synchronizationTimeout = synchronizationTimeoutSeconds
        self.receiptClock = receiptClock
        super.init()
    }

    package override var description: String {
        "GS3ForegroundCoreBluetoothTransport(state: redacted)"
    }

    package override var debugDescription: String { description }

    package var customMirror: Mirror {
        Mirror(
            self,
            children: ["state": "redacted"],
            displayStyle: .class
        )
    }

    public func installEventHandler(
        _ handler: @escaping @Sendable (GS3ForegroundTransportEvent) -> Void
    ) async {
        await enqueue {
            self.eventHandler = handler
        }
    }

    public func connectKnownPeripheral() async {
        await enqueue {
            guard self.phase == .idle else {
                self.rejectLocked(.stateInvariant)
                return
            }
            self.resetConnectionStateLocked()
            self.phase = .waitingForPower
            self.scheduleOperationTimeoutLocked()
            if let authorizationError = BluetoothAuthorizationMapping.transportError(
                for: CBManager.authorization
            ) {
                self.reportDisconnectedLocked(
                    self.disconnectReason(for: authorizationError)
                )
                return
            }
            self.ensureCentralLocked()
            self.connectIfPoweredOnLocked()
        }
    }

    public func ensureDisconnected() async {
        await enqueue {
            self.cancelTimeoutsLocked()
            guard let peripheral = self.peripheral,
                  peripheral.state != .disconnected,
                  let central = self.central else {
                self.resetConnectionStateLocked()
                self.emit(.transportDisconnected)
                return
            }
            guard self.phase != .disconnecting else { return }
            self.controlledDisconnect = true
            self.pendingDisconnectReason = nil
            self.queuedHistoryPlan = nil
            self.phase = .disconnecting
            self.scheduleDisconnectCompletionTimeoutLocked()
            central.cancelPeripheralConnection(peripheral)
        }
    }

    public func discoverGS3Service() async {
        await enqueue {
            guard self.phase == .connected, let peripheral = self.peripheral else {
                self.rejectLocked(.stateInvariant)
                return
            }
            self.phase = .discoveringService
            self.scheduleOperationTimeoutLocked()
            peripheral.discoverServices([Self.serviceUUID])
        }
    }

    public func discoverGS3Characteristics() async {
        await enqueue {
            guard self.phase == .serviceDiscovered,
                  let peripheral = self.peripheral,
                  let service = self.service else {
                self.rejectLocked(.stateInvariant)
                return
            }
            self.phase = .discoveringCharacteristics
            self.scheduleOperationTimeoutLocked()
            peripheral.discoverCharacteristics(
                [Self.notificationUUID, Self.transmissionUUID],
                for: service
            )
        }
    }

    public func subscribeToGS3Notifications() async {
        await enqueue {
            guard self.phase == .characteristicsDiscovered,
                  let peripheral = self.peripheral,
                  let characteristic = self.notificationCharacteristic else {
                self.rejectLocked(.stateInvariant)
                return
            }
            self.phase = .subscribing
            self.scheduleOperationTimeoutLocked()
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    public func authenticateConnection() async {
        await enqueue {
            guard self.phase == .subscribed,
                  self.authenticationWriteCallCount == 0,
                  self.effectiveDataWriteCallCount == 0,
                  self.inFlightCommand == nil else {
                self.rejectLocked(.requestInvariant)
                return
            }
            do {
                let frame = try self.material.authenticationFrame()
                guard frame.byteCount == 38 else {
                    self.rejectLocked(.requestInvariant)
                    return
                }
                self.phase = .authenticating
                self.authenticationWriteCallCount = 1
                if self.transmitLocked(frame, command: .authentication) {
                    self.scheduleResponseTimeoutLocked(
                        after: self.operationTimeout
                    )
                }
            } catch {
                self.rejectLocked(.requestInvariant)
            }
        }
    }

    public func requestEffectiveData(_ plan: HistoryRequestPlan) async {
        await enqueue {
            guard self.phase == .authenticated,
                  self.authenticationAccepted,
                  self.effectiveDataWriteCallCount == 0,
                  self.queuedHistoryPlan == nil else {
                self.rejectLocked(.requestInvariant)
                return
            }
            if self.inFlightCommand == .authentication {
                self.queuedHistoryPlan = plan
                return
            }
            guard self.inFlightCommand == nil else {
                self.rejectLocked(.requestInvariant)
                return
            }
            self.transmitEffectiveDataLocked(plan)
        }
    }

    private func enqueue(_ body: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                body()
                continuation.resume()
            }
        }
    }

    private func ensureCentralLocked() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: queue, options: nil)
    }

    private func connectIfPoweredOnLocked() {
        guard phase == .waitingForPower, let central else { return }
        switch central.state {
        case .poweredOn:
            guard let found = central.retrievePeripherals(
                withIdentifiers: [peripheralID]
            ).first else {
                reportDisconnectedLocked(.timeout)
                return
            }
            peripheral = found
            found.delegate = self
            guard found.state == .disconnected else {
                pendingDisconnectReason = .timeout
                controlledDisconnect = false
                phase = .disconnecting
                scheduleDisconnectCompletionTimeoutLocked()
                central.cancelPeripheralConnection(found)
                return
            }
            phase = .connecting
            scheduleOperationTimeoutLocked()
            central.connect(found, options: nil)
        case .unauthorized:
            reportDisconnectedLocked(.permissionDenied)
        case .poweredOff, .unsupported, .resetting:
            reportDisconnectedLocked(.bluetoothUnavailable)
        case .unknown:
            break
        @unknown default:
            reportDisconnectedLocked(.bluetoothUnavailable)
        }
    }

    private func transmitEffectiveDataLocked(_ plan: HistoryRequestPlan) {
        do {
            let frame = try material.effectiveDataFrame(
                startingIndex: plan.startingIndex
            )
            guard frame.byteCount == 7,
                  authenticationWriteCallCount == 1,
                  effectiveDataWriteCallCount == 0 else {
                rejectLocked(.requestInvariant)
                return
            }
            phase = .awaitingHistory
            effectiveDataWriteCallCount = 1
            if transmitLocked(frame, command: .effectiveData) {
                scheduleResponseTimeoutLocked(after: synchronizationTimeout)
            }
        } catch {
            rejectLocked(.requestInvariant)
        }
    }

    /// The sole characteristic-write site. Both callers supply frames produced
    /// by the two typed V3 encoders after per-connection count guards pass.
    private func transmitLocked(
        _ frame: EncodedFrame,
        command: InFlightCommand
    ) -> Bool {
        guard let peripheral,
              let characteristic = transmissionCharacteristic,
              characteristic.uuid == Self.transmissionUUID,
              characteristic.properties.contains(.write),
              inFlightCommand == nil else {
            rejectLocked(.stateInvariant)
            return false
        }
        inFlightCommand = command
        scheduleOperationTimeoutLocked()
        peripheral.writeValue(
            Data(frame.bytes),
            for: characteristic,
            type: .withResponse
        )
        return true
    }

    private func handleControlLocked(
        _ response: V3ControlResponse,
        frameByteCount: Int,
        timingWindow: GS3ProtocolTimingWindow
    ) {
        switch response {
        case .authenticationAccepted:
            guard phase == .authenticating,
                  authenticationWriteCallCount == 1,
                  !authenticationAccepted else {
                rejectLocked(
                    .stateInvariant,
                    frameByteCount: frameByteCount,
                    timingWindow: timingWindow
                )
                return
            }
            authenticationAccepted = true
            phase = .authenticated
            scheduleResponseTimeoutLocked(after: operationTimeout)
            emit(.authenticationAccepted)

        case .authenticationRejected:
            guard phase == .authenticating else {
                rejectLocked(
                    .stateInvariant,
                    frameByteCount: frameByteCount,
                    timingWindow: timingWindow
                )
                return
            }
            cancelResponseTimeoutLocked()
            emit(.authenticationRejected)

        case .effectiveDataAcknowledgement(let code, let detail):
            guard (phase == .awaitingHistory || phase == .streaming),
                  effectiveDataWriteCallCount == 1,
                  !historyControlAcknowledged,
                  code == 0x01,
                  detail == 0x00 else {
                rejectLocked(
                    .stateInvariant,
                    frameByteCount: frameByteCount,
                    timingWindow: timingWindow
                )
                return
            }
            historyControlAcknowledged = true
            phase = .streaming
            scheduleResponseTimeoutLocked(after: synchronizationTimeout)
            emitHistoryReadyIfPossibleLocked()
        }
    }

    private func emitHistoryReadyIfPossibleLocked() {
        guard effectiveDataWriteAcknowledged,
              historyControlAcknowledged,
              !historyReadyEmitted else { return }
        historyReadyEmitted = true
        emit(.historyAcknowledged)
    }

    private func handleGlucoseLocked(
        _ batch: V3GlucoseBatch,
        frameByteCount: Int,
        timingWindow: GS3ProtocolTimingWindow
    ) {
        guard authenticationAccepted,
              effectiveDataWriteCallCount == 1,
              phase == .awaitingHistory || phase == .streaming else {
            rejectLocked(
                .stateInvariant,
                frameByteCount: frameByteCount,
                timingWindow: timingWindow
            )
            return
        }
        if batch.source == .liveNotification {
            guard historyReadyEmitted else {
                rejectLocked(
                    .stateInvariant,
                    frameByteCount: frameByteCount,
                    timingWindow: timingWindow
                )
                return
            }
            phase = .streaming
            cancelResponseTimeoutLocked()
        }
        hasReceivedGlucoseBatch = true
        emit(.glucoseBatch(batch, receivedAt: receiptClock()))
    }

    private func rejectLocked(
        _ origin: GS3ProtocolRejectionOrigin,
        frameByteCount: Int? = nil,
        timingWindow: GS3ProtocolTimingWindow? = nil,
        frameCategory: GS3ProtocolFrameCategory? = nil
    ) {
        if !protocolRejectionReported {
            protocolRejectionReported = true
            let window = timingWindow ?? diagnosticTimingWindowLocked()
            let rejection: GS3ProtocolRejection
            if let frameByteCount {
                rejection = GS3ProtocolRejection(
                    origin: origin,
                    frameCategory: frameCategory
                        ?? .classify(byteCount: frameByteCount),
                    frameByteCount: frameByteCount,
                    timingWindow: window
                )
            } else {
                rejection = GS3ProtocolRejection(
                    origin: origin,
                    frameCategory: frameCategory ?? .unavailable,
                    timingWindow: window
                )
            }
            emit(.protocolRejected(rejection))
        }
        failLocked(.protocolViolation)
    }

    private func diagnosticTimingWindowLocked() -> GS3ProtocolTimingWindow {
        switch phase {
        case .idle, .waitingForPower, .connecting, .connected,
             .discoveringService, .serviceDiscovered,
             .discoveringCharacteristics, .characteristicsDiscovered,
             .subscribing, .subscribed:
            .connectionSetup
        case .authenticating:
            .authentication
        case .authenticated:
            .authenticated
        case .awaitingHistory:
            inFlightCommand == .effectiveData && !effectiveDataWriteAcknowledged
                ? .historyWritePending
                : .historyResponse
        case .streaming:
            .streaming
        case .disconnecting:
            .disconnecting
        }
    }

    private func failLocked(_ reason: GS3DisconnectReason) {
        guard phase != .disconnecting else { return }
        cancelTimeoutsLocked()
        pendingDisconnectReason = reason
        controlledDisconnect = false
        queuedHistoryPlan = nil
        guard let peripheral,
              peripheral.state != .disconnected,
              let central else {
            reportDisconnectedLocked(reason)
            return
        }
        phase = .disconnecting
        scheduleDisconnectCompletionTimeoutLocked()
        central.cancelPeripheralConnection(peripheral)
    }

    private func reportDisconnectedLocked(_ reason: GS3DisconnectReason) {
        resetConnectionStateLocked()
        emit(.disconnected(reason))
    }

    private func completeDisconnectionLocked(error: Error?) {
        let event: GS3ForegroundTransportEvent
        if controlledDisconnect {
            event = .transportDisconnected
        } else if let pendingDisconnectReason {
            event = .disconnected(pendingDisconnectReason)
        } else {
            event = .disconnected(disconnectReason(for: error))
        }
        resetConnectionStateLocked()
        emit(event)
    }

    private func disconnectReason(for error: Error?) -> GS3DisconnectReason {
        guard let error else { return .linkLoss }
        if let transportError = error as? TransportError {
            return disconnectReason(for: transportError)
        }
        let nsError = error as NSError
        return nsError.domain == CBErrorDomain
            ? .coreBluetooth(code: nsError.code)
            : .otherRedacted
    }

    private func disconnectReason(for error: TransportError) -> GS3DisconnectReason {
        switch error {
        case .permissionDenied: .permissionDenied
        case .bluetoothUnavailable: .bluetoothUnavailable
        case .timeout: .timeout
        case .disconnected: .linkLoss
        default: .otherRedacted
        }
    }

    private func emit(_ event: GS3ForegroundTransportEvent) {
        eventHandler?(event)
    }

    private func scheduleOperationTimeoutLocked() {
        let token = UUID()
        operationToken = token
        queue.asyncAfter(deadline: .now() + operationTimeout) { [weak self] in
            guard let self, self.operationToken == token else { return }
            self.operationToken = nil
            self.failLocked(.timeout)
        }
    }

    private func cancelOperationTimeoutLocked() {
        operationToken = nil
    }

    private func scheduleResponseTimeoutLocked(after delay: TimeInterval) {
        let token = UUID()
        responseToken = token
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.responseToken == token else { return }
            self.responseToken = nil
            self.failLocked(.timeout)
        }
    }

    private func cancelResponseTimeoutLocked() {
        responseToken = nil
    }

    private func cancelTimeoutsLocked() {
        operationToken = nil
        responseToken = nil
    }

    /// CoreBluetooth normally completes cancellation through
    /// `didDisconnectPeripheral`. Keep the lifecycle bounded if that callback
    /// is lost; late callbacks are rejected by object identity after reset.
    private func scheduleDisconnectCompletionTimeoutLocked() {
        let token = UUID()
        operationToken = token
        queue.asyncAfter(deadline: .now() + operationTimeout) { [weak self] in
            guard let self,
                  self.operationToken == token,
                  self.phase == .disconnecting else { return }
            self.operationToken = nil
            self.completeDisconnectionLocked(error: TransportError.timeout)
        }
    }

    private func resetConnectionStateLocked() {
        cancelTimeoutsLocked()
        peripheral?.delegate = nil
        peripheral = nil
        service = nil
        notificationCharacteristic = nil
        transmissionCharacteristic = nil
        phase = .idle
        pendingDisconnectReason = nil
        controlledDisconnect = false
        inFlightCommand = nil
        queuedHistoryPlan = nil
        authenticationWriteCallCount = 0
        effectiveDataWriteCallCount = 0
        authenticationAccepted = false
        effectiveDataWriteAcknowledged = false
        historyControlAcknowledged = false
        historyReadyEmitted = false
        hasReceivedGlucoseBatch = false
        historyPreambleCount = 0
        protocolRejectionReported = false
    }
}

/// Sole public construction path for the reviewed known-peer foreground slice.
/// It always couples the typed CoreBluetooth adapter to the coordinator's real
/// shared-process ownership provider and bounded reconnect scheduler.
public enum GS3ForegroundSessionFactory: Sendable {
    public static func makeKnownPeripheralController(
        configuration: GS3ForegroundSessionConfiguration,
        store: any SugarmanStoring,
        peripheralID: UUID,
        material: V3ActiveSessionMaterial,
        callbacks: GS3ForegroundSessionCallbacks = GS3ForegroundSessionCallbacks()
    ) -> any GS3ForegroundSessionControlling {
        let transport = GS3ForegroundCoreBluetoothTransport(
            peripheralID: peripheralID,
            material: material
        )
        return GS3ForegroundSessionCoordinator(
            configuration: configuration,
            store: store,
            transport: transport,
            callbacks: callbacks
        )
    }
}

extension GS3ForegroundCoreBluetoothTransport: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard self.central === central else { return }
        if phase == .waitingForPower {
            connectIfPoweredOnLocked()
            return
        }
        guard phase != .idle else { return }
        switch central.state {
        case .unauthorized:
            failLocked(.permissionDenied)
        case .poweredOff, .unsupported, .resetting:
            failLocked(.bluetoothUnavailable)
        case .poweredOn, .unknown:
            break
        @unknown default:
            failLocked(.bluetoothUnavailable)
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        guard self.central === central,
              self.peripheral === peripheral,
              phase == .connecting else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        cancelOperationTimeoutLocked()
        phase = .connected
        emit(.connected)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard self.central === central,
              self.peripheral === peripheral else { return }
        completeDisconnectionLocked(error: error)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard self.central === central,
              self.peripheral === peripheral else { return }
        completeDisconnectionLocked(error: error)
    }
}

extension GS3ForegroundCoreBluetoothTransport: CBPeripheralDelegate {
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard self.peripheral === peripheral,
              phase == .discoveringService else { return }
        if let error {
            failLocked(disconnectReason(for: error))
            return
        }
        guard let service = peripheral.services?.first(where: {
            $0.uuid == Self.serviceUUID
        }) else {
            rejectLocked(.stateInvariant)
            return
        }
        cancelOperationTimeoutLocked()
        self.service = service
        phase = .serviceDiscovered
        emit(.servicesDiscovered)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard self.peripheral === peripheral,
              self.service === service,
              phase == .discoveringCharacteristics else { return }
        if let error {
            failLocked(disconnectReason(for: error))
            return
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.notificationUUID,
               characteristic.properties.contains(.notify) {
                notificationCharacteristic = characteristic
            } else if characteristic.uuid == Self.transmissionUUID,
                      characteristic.properties.contains(.write) {
                transmissionCharacteristic = characteristic
            }
        }
        guard notificationCharacteristic != nil,
              transmissionCharacteristic != nil else {
            rejectLocked(.stateInvariant)
            return
        }
        cancelOperationTimeoutLocked()
        phase = .characteristicsDiscovered
        emit(.characteristicsDiscovered)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard self.peripheral === peripheral,
              self.notificationCharacteristic === characteristic,
              characteristic.uuid == Self.notificationUUID,
              phase == .subscribing else { return }
        if let error {
            failLocked(disconnectReason(for: error))
            return
        }
        guard characteristic.isNotifying else {
            rejectLocked(.stateInvariant)
            return
        }
        cancelOperationTimeoutLocked()
        phase = .subscribed
        emit(.notificationSubscriptionEnabled)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard self.peripheral === peripheral,
              self.transmissionCharacteristic === characteristic else { return }
        guard phase != .disconnecting else { return }
        guard characteristic.uuid == Self.transmissionUUID,
              let completed = inFlightCommand else {
            rejectLocked(.writeCallbackInvariant)
            return
        }
        if let error {
            failLocked(disconnectReason(for: error))
            return
        }
        cancelOperationTimeoutLocked()
        inFlightCommand = nil
        switch completed {
        case .authentication:
            emit(.authenticationWriteAcknowledged)
            if let plan = queuedHistoryPlan {
                queuedHistoryPlan = nil
                transmitEffectiveDataLocked(plan)
            }
        case .effectiveData:
            effectiveDataWriteAcknowledged = true
            emit(.historyWriteAcknowledged)
            emitHistoryReadyIfPossibleLocked()
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard self.peripheral === peripheral,
              self.notificationCharacteristic === characteristic,
              characteristic.uuid == Self.notificationUUID else { return }
        guard phase != .disconnecting else { return }
        if let error {
            failLocked(disconnectReason(for: error))
            return
        }
        guard let value = characteristic.value else {
            rejectLocked(
                .inboundClassification,
                frameCategory: .missing
            )
            return
        }
        do {
            let frame = EncodedFrame(bytes: [UInt8](value))
            let timingWindow = diagnosticTimingWindowLocked()
            let context = V3ForegroundInboundContext(
                isAwaitingHistory: phase == .awaitingHistory,
                authenticationAccepted: authenticationAccepted,
                historyWriteCallCount: effectiveDataWriteCallCount,
                historyWriteAcknowledgementPending:
                    inFlightCommand == .effectiveData
                        && !effectiveDataWriteAcknowledged,
                historyControlAcknowledged: historyControlAcknowledged,
                historyReadyEmitted: historyReadyEmitted,
                hasReceivedGlucoseBatch: hasReceivedGlucoseBatch,
                historyPreambleCount: historyPreambleCount
            )
            switch try V3ForegroundInboundClassifier.classify(
                frame,
                using: material,
                context: context
            ) {
            case .control(let response):
                handleControlLocked(
                    response,
                    frameByteCount: frame.byteCount,
                    timingWindow: timingWindow
                )
            case .glucose(let batch):
                handleGlucoseLocked(
                    batch,
                    frameByteCount: frame.byteCount,
                    timingWindow: timingWindow
                )
            case .observedHistoryPreamble:
                historyPreambleCount = 1
                emit(.historyPreambleObserved)
            }
        } catch {
            // Only the exact, host-tested history-preamble shape and timing
            // above is nonterminal. Every other unknown or malformed command
            // remains terminal.
            rejectLocked(
                .inboundClassification,
                frameByteCount: value.count,
                timingWindow: diagnosticTimingWindowLocked()
            )
        }
    }
}
#endif
