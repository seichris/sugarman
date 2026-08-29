// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Pure transport state machine. One in-flight command. Mutating peripheral
/// operations (authentication, binding, activation, reset, expiry, secret-key)
/// are refused. Designed to run on a dedicated serial queue.
///
/// Restoration is simulated in tests by constructing a machine already in
/// `.scanning`, `.connecting`, `.discovering`, or `.subscribed` and injecting
/// the same inputs CoreBluetooth would deliver after `willRestoreState`.
/// This is not a live CoreBluetooth restoration implementation.
public struct TransportStateMachine: Sendable, Equatable {
    public var state: TransportState
    public var inFlight: Bool
    public var peripheralID: UUID?
    public let queueLabel = "app.sugarman.ios.gs3.transport"

    public init(state: TransportState = .idle, inFlight: Bool = false, peripheralID: UUID? = nil) {
        self.state = state
        self.inFlight = inFlight
        self.peripheralID = peripheralID
    }

    public mutating func send(_ input: TransportInput) -> [TransportEffect] {
        switch input {
        case .requestAuthentication:
            return failClosed(.authenticationUnimplemented)
        case .requestBinding:
            return failClosed(.bindingUnimplemented)
        case .bluetoothUnavailable:
            inFlight = false
            state = .ended
            return [.stopScan, .fail(.bluetoothUnavailable)]
        case .permissionDenied:
            inFlight = false
            state = .ended
            return [.stopScan, .fail(.permissionDenied)]
        case .cancel:
            inFlight = false
            let id = peripheralID
            state = .ended
            var effects: [TransportEffect] = [.stopScan]
            if let id {
                effects.append(.cancelConnection(id))
            }
            return effects
        case .timeout:
            return handleTimeout()
        case .disconnect:
            inFlight = false
            if state == .ended {
                return []
            }
            state = .backoff
            return [.waitBackoff]
        default:
            break
        }

        if inFlight && isCommandStart(input) && !isAllowedConnectWhileScanning(input) {
            return [.fail(.commandInFlight)]
        }

        switch (state, input) {
        case (.idle, .startScan), (.backoff, .startScan):
            inFlight = true
            state = .scanning
            return [.startScan]
        case (.scanning, .advertisement(let id)):
            peripheralID = id
            return []
        case (.scanning, .connect(let id)):
            peripheralID = id
            state = .connecting
            inFlight = true
            return [.stopScan, .connect(id)]
        case (.idle, .connect(let id)), (.backoff, .connect(let id)):
            peripheralID = id
            state = .connecting
            inFlight = true
            return [.connect(id)]
        case (.connecting, .connected):
            state = .discovering
            inFlight = true
            return [.discoverServices]
        case (.discovering, .servicesDiscovered):
            inFlight = true
            return [.discoverCharacteristics]
        case (.discovering, .characteristicsDiscovered):
            state = .subscribed
            inFlight = true
            return [.subscribe]
        case (.subscribed, .subscribed):
            inFlight = false
            return []
        case (.subscribed, .readComplete):
            inFlight = false
            return []
        case (.authenticating, _), (.binding, _), (.synchronizing, _), (.live, _):
            // These states exist so later milestones can extend the machine.
            // M0 cannot enter them without a refused mutating input.
            return failClosed(.mutatingOperationRefused)
        default:
            return [.fail(.invalidTransition(from: state))]
        }
    }

    public mutating func beginAllowlistedRead(_ characteristic: UUID) -> [TransportEffect] {
        guard DocumentedReadableCharacteristic.isAllowlisted(characteristic) else {
            return failClosed(.mutatingOperationRefused)
        }
        guard state == .subscribed else {
            return [.fail(.invalidTransition(from: state))]
        }
        if inFlight {
            return [.fail(.commandInFlight)]
        }
        inFlight = true
        return [.read(characteristic)]
    }

    /// Command starts occupy the single in-flight slot: `startScan`, `connect`,
    /// and allowlisted reads (`beginAllowlistedRead`). Connect while scanning
    /// is the allowed transition from `.scanning` and is not blocked.
    public func isCommandStart(_ input: TransportInput) -> Bool {
        switch input {
        case .startScan, .connect:
            return true
        default:
            return false
        }
    }

    private func isAllowedConnectWhileScanning(_ input: TransportInput) -> Bool {
        if case .connect = input, state == .scanning {
            return true
        }
        return false
    }

    private mutating func handleTimeout() -> [TransportEffect] {
        inFlight = false
        switch state {
        case .scanning, .connecting, .discovering:
            state = .backoff
            return [.stopScan, .waitBackoff]
        default:
            state = .backoff
            return [.waitBackoff]
        }
    }

    private mutating func failClosed(_ error: TransportError) -> [TransportEffect] {
        inFlight = false
        return [.fail(error)]
    }
}

/// Serial-queue owner wrapping the state machine. The CoreBluetooth adapter
/// hops onto `queue` and must not log frame bytes or issue characteristic writes.
public final class GS3TransportSession: @unchecked Sendable {
    public let queue: DispatchQueue
    private var machine: TransportStateMachine
    private let runtime: any BluetoothRuntime

    public init(runtime: any BluetoothRuntime, machine: TransportStateMachine = TransportStateMachine()) {
        self.runtime = runtime
        self.machine = machine
        self.queue = DispatchQueue(label: machine.queueLabel)
    }

    public var state: TransportState {
        queue.sync { machine.state }
    }

    public func handle(_ input: TransportInput) async throws {
        let effects: [TransportEffect] = queue.sync {
            machine.send(input)
        }
        for effect in effects {
            try await runtime.perform(effect)
        }
    }

    public func readDocumentedCharacteristic(_ uuid: UUID) async throws {
        let effects: [TransportEffect] = queue.sync {
            machine.beginAllowlistedRead(uuid)
        }
        for effect in effects {
            try await runtime.perform(effect)
        }
    }
}
