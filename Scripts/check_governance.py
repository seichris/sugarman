#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Sugarman contributors
"""Fail CI if licence, provenance, or binary-exclusion rules are broken."""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []

BINARY_SUFFIXES = {
    ".so",
    ".aar",
    ".apk",
    ".apks",
    ".aab",
    ".dex",
    ".jar",
    ".dylib",
    ".a",
    ".o",
    ".elf",
}

TEXTISH = {
    ".swift",
    ".md",
    ".json",
    ".yml",
    ".yaml",
    ".toml",
    ".txt",
    ".plist",
    ".entitlements",
    ".xcstrings",
    ".gitignore",
    ".gitmodules",
}

SKIP_DIR_NAMES = {
    ".git",
    ".build",
    ".swiftpm",
    "DerivedData",
    "upstream",
    "private-evidence",
}


def error(message: str) -> None:
    ERRORS.append(message)


def iter_repo_files() -> list[Path]:
    files: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIR_NAMES]
        path = Path(dirpath)
        rel = path.relative_to(ROOT)
        if rel.parts and rel.parts[0] == "upstream":
            continue
        for name in filenames:
            files.append(path / name)
    return files


def check_licence() -> None:
    license_path = ROOT / "LICENSE"
    if not license_path.is_file():
        error("missing root LICENSE")
        return
    text = license_path.read_text(encoding="utf-8", errors="replace")
    if "GNU GENERAL PUBLIC LICENSE" not in text or "Version 3" not in text:
        error("LICENSE is not GPLv3 text")
    readme = (ROOT / "README.md").read_text(encoding="utf-8", errors="replace")
    if "GPL-3.0-or-later" not in readme:
        error("README.md must declare GPL-3.0-or-later")
    pkg = (ROOT / "Package.swift").read_text(encoding="utf-8", errors="replace")
    if "GPL-3.0-or-later" not in pkg:
        error("Package.swift must declare GPL-3.0-or-later")
    if not (ROOT / "THIRD_PARTY.md").is_file():
        error("missing THIRD_PARTY.md")


def check_provenance() -> None:
    registry_path = ROOT / "docs/provenance/registry.json"
    schema_path = ROOT / "docs/provenance/schema.json"
    if not registry_path.is_file():
        error("missing docs/provenance/registry.json")
        return
    if not schema_path.is_file():
        error("missing docs/provenance/schema.json")
        return
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    if registry.get("project_licence") != "GPL-3.0-or-later":
        error("provenance registry project_licence must be GPL-3.0-or-later")
    if "records" not in registry or not isinstance(registry["records"], list):
        error("provenance registry must contain a records array")
    required = {
        "id",
        "upstream_project",
        "upstream_url",
        "pinned_commit",
        "source_path",
        "source_blob_sha256",
        "copyright_holders",
        "history_reviewed",
        "file_header_licence",
        "repository_licence",
        "purpose_and_behavior_taken",
        "reuse_mode",
        "sugarman_destination_path",
        "modification_date",
        "author",
        "fixtures_origin",
        "fixtures_capture_sha256",
        "reviewer",
        "legal_review_status",
    }
    allowed_modes = {"verbatim", "adapted", "behavioral", "independently observed"}
    for index, record in enumerate(registry.get("records", [])):
        missing = required - set(record)
        if missing:
            error(f"provenance record[{index}] missing fields: {sorted(missing)}")
        mode = record.get("reuse_mode")
        if mode not in allowed_modes:
            error(f"provenance record[{index}] has invalid reuse_mode {mode!r}")


def check_binaries_and_resources() -> None:
    config_files: list[Path] = []
    for path in iter_repo_files():
        rel = path.relative_to(ROOT).as_posix()
        suffix = path.suffix.lower()
        if suffix in BINARY_SUFFIXES:
            error(f"unexplained binary in repository: {rel}")
        if path.name.lower().endswith(".apk"):
            error(f"APK must not be committed: {rel}")
        if suffix in {".yml", ".yaml", ".pbxproj", ".swift"} or path.name in {
            "Package.swift",
            "project.yml",
            "Package.resolved",
        }:
            config_files.append(path)

    reference_pattern = re.compile(
        r"(upstream/|\.so\b|\.aar\b|\.apk\b)", re.IGNORECASE
    )
    for path in config_files:
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith("Scripts/") or rel.startswith(".github/"):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if "upstream/" in text and path.suffix in {".swift", ".pbxproj"}:
            # comments in Swift that mention upstream as a non-path are ok if
            # they do not look like a file resource.
            if re.search(r'["\'][^"\']*upstream/', text) or "path = upstream" in text:
                error(f"{rel} references upstream/ as a resource or path")
        if path.name in {"project.yml", "Package.swift"} or path.suffix == ".pbxproj":
            for match in reference_pattern.finditer(text):
                snippet = text[max(0, match.start() - 40) : match.end() + 40]
                if "must never" in snippet.lower() or "reference-only" in snippet.lower():
                    continue
                if "upstream/" in match.group(0) and path.name == "project.yml":
                    error(f"{rel} must not list upstream/ as a target path")
                if match.group(0).lower() in {".so", ".aar", ".apk"} and "resources" in snippet.lower():
                    error(f"{rel} appears to reference a forbidden binary resource")

    xcodeproj = ROOT / "Sugarman.xcodeproj/project.pbxproj"
    if xcodeproj.is_file():
        pbx = xcodeproj.read_text(encoding="utf-8", errors="replace")
        if "upstream/" in pbx:
            error("Xcode project references upstream/")
        if re.search(r"\.(so|aar|apk)\b", pbx, re.IGNORECASE):
            error("Xcode project references .so/.aar/APK")
        if "audio" in pbx and "UIBackgroundModes" in pbx:
            # coarse; also check Info.plist
            pass

    for plist in (ROOT / "Apps").rglob("Info.plist"):
        text = plist.read_text(encoding="utf-8", errors="replace")
        if re.search(r"<string>\s*audio\s*</string>", text):
            error(f"{plist.relative_to(ROOT)} enables audio background mode")
        if plist == ROOT / "Apps/Sugarman/Info.plist" and "bluetooth-central" not in text:
            error(f"{plist.relative_to(ROOT)} missing bluetooth-central")
        if plist == ROOT / "Apps/SugarmanProbe/Info.plist" and "bluetooth-central" in text:
            error("developer probe must remain foreground-only")


def check_no_write_api() -> None:
    characteristic_write = re.compile(
        r"\b(writeValue\s*\(|writeCharacteristic\s*\()"
    )
    protocol_write_function = re.compile(r"\bfunc\s+write[A-Z]")
    live_cmd = re.compile(
        r"\b(activateSensor|resetSensor|writeSecretKey|authWrite|bindAccountOnSensor)\s*\("
    )

    guarded_protocol_roots = {
        ROOT / "Sources/SugarmanDiagnostics",
        ROOT / "Sources/GS3Transport",
        ROOT / "Sources/GS3Protocol",
        ROOT / "Sources/GS3DeveloperProbe",
        ROOT / "Sources/GS3DeviceTesting",
    }
    probe_adapter = ROOT / "Apps/SugarmanProbe/V3ProbeBluetoothRuntime.swift"
    provisioning_scanner = (
        ROOT / "Sources/GS3DeviceTesting/GS3ProbeProvisioningScanner.swift"
    )
    production_adapter = (
        ROOT / "Sources/GS3Transport/GS3ForegroundCoreBluetoothTransport.swift"
    )
    allowed_characteristic_writers = {probe_adapter, production_adapter}
    for base in (ROOT / "Sources", ROOT / "Apps"):
        if not base.is_dir():
            continue
        for path in base.rglob("*.swift"):
            text = path.read_text(encoding="utf-8", errors="replace")
            rel = path.relative_to(ROOT).as_posix()
            if (
                characteristic_write.search(text)
                and path not in allowed_characteristic_writers
            ):
                error(f"forbidden characteristic-write API in {rel}")
            if live_cmd.search(text):
                error(f"live sensor command API in {rel}")
            if (
                "import CoreBluetooth" in text
                and not path.is_relative_to(ROOT / "Sources/GS3Transport")
                and not path.is_relative_to(ROOT / "Sources/GS3DeviceTesting")
                and path != probe_adapter
            ):
                error(f"CoreBluetooth must remain confined to GS3Transport: {rel}")
            if any(path.is_relative_to(root) for root in guarded_protocol_roots):
                if protocol_write_function.search(text):
                    error(f"forbidden protocol write function in {rel}")

    if not probe_adapter.is_file():
        error("missing typed developer-probe CoreBluetooth adapter")
    else:
        body = probe_adapter.read_text(encoding="utf-8", errors="replace")
        if body.count(".writeValue(") != 1:
            error("developer probe adapter must contain exactly one characteristic write site")
        for required in (
            "case .authentication(let typedFrame)",
            "case .effectiveData(let typedFrame)",
            "type: .withResponse",
            'CBUUID(string: "FF31")',
            'CBUUID(string: "FF32")',
            "private var inFlightWrite: ProbeWriteKind?",
            "private var queuedTransmission: V3ProbeTransmission?",
            "authenticationWriteCallCount == 0",
            "effectiveDataWriteCallCount == 0",
            "emitDiagnostic(diagnostic.description)",
            "RX FF31 delivered while CoreBluetooth awaited FF32",
            "effectiveDataWriteAcknowledgementPending: inFlightWrite == .effectiveData",
            "probe?.completionGatePassed == true",
            "V3ProbeDisconnectDiagnostic(",
            "nsError.domain == CBErrorDomain",
            "runStartedAtUptimeNanoseconds",
            "emit(.failed(diagnostic.failureDescription))",
        ):
            if required not in body:
                error(f"developer probe adapter missing strict boundary: {required}")
        for forbidden in (
            ".withoutResponse",
            "0x35",
            "0x30",
            "0xF0",
            "CBCentralManagerOptionRestoreIdentifierKey",
        ):
            if forbidden in body:
                error(f"developer probe adapter contains forbidden surface: {forbidden}")

    if not production_adapter.is_file():
        error("missing typed production foreground CoreBluetooth adapter")
    else:
        body = production_adapter.read_text(encoding="utf-8", errors="replace")
        if body.count(".writeValue(") != 1:
            error("production adapter must contain exactly one characteristic write site")
        for required in (
            "connectKnownPeripheral()",
            "retrievePeripherals(",
            "withIdentifiers: [peripheralID]",
            'CBUUID(string: "FF30")',
            'CBUUID(string: "FF31")',
            'CBUUID(string: "FF32")',
            "V3ActiveSessionMaterial",
            "public enum GS3ForegroundSessionFactory",
            "makeKnownPeripheralController(",
            "material.authenticationFrame()",
            "material.effectiveDataFrame(",
            "authenticationWriteCallCount == 0",
            "effectiveDataWriteCallCount == 0",
            "self.phase == .authenticated",
            "private var queuedHistoryPlan: HistoryRequestPlan?",
            "authenticationWriteCallCount == 1",
            "effectiveDataWriteCallCount == 1",
            "!historyControlAcknowledged",
            "effectiveDataWriteAcknowledged",
            "emitHistoryReadyIfPossibleLocked()",
            "guard historyReadyEmitted else",
            "found.state == .disconnected",
            "scheduleResponseTimeoutLocked(after: operationTimeout)",
            "code == 0x01",
            "detail == 0x00",
            "type: .withResponse",
            "self.queue = DispatchQueue(label: Self.queueLabel)",
            "scheduleDisconnectCompletionTimeoutLocked()",
            "self.central === central",
            "self.notificationCharacteristic === characteristic",
            "self.transmissionCharacteristic === characteristic",
            "GS3ForegroundCoreBluetoothTransport(state: redacted)",
            "CustomReflectable",
            "failLocked(.protocolViolation)",
        ):
            if required not in body:
                error(f"production adapter missing strict boundary: {required}")
        for forbidden in (
            "scanForPeripherals",
            ".withoutResponse",
            "CBCentralManagerOptionRestoreIdentifierKey",
            "writeCharacteristic",
            "activateSensor(",
            "bindAccountOnSensor(",
            "resetSensor(",
            "writeSecretKey(",
        ):
            if forbidden in body:
                error(f"production adapter contains forbidden surface: {forbidden}")
        if body.count("guard phase != .disconnecting else { return }") < 2:
            error("production adapter must ignore write/value callbacks while disconnecting")

    if not provisioning_scanner.is_file():
        error("missing device-test Probe JSON scan-only provisioning adapter")
    else:
        body = provisioning_scanner.read_text(encoding="utf-8", errors="replace")
        for required in (
            "GS3DeviceTestExternalOwnershipGate",
            "requireConfirmation()",
            "GS3ProbeBridgeDiscoveryAccumulator",
            "SharedSensorOwnerLease.acquire()",
            "scanWindowSeconds: TimeInterval = 10",
            "scanForPeripherals(",
            "CBCentralManagerScanOptionAllowDuplicatesKey: true",
            "central?.stopScan()",
            "ownerLease?.release()",
        ):
            if required not in body:
                error(f"scan-only provisioning adapter missing boundary: {required}")
        if body.count("scanForPeripherals(") != 1:
            error("scan-only provisioning adapter must contain exactly one scan site")
        for forbidden in (
            ".connect(",
            "cancelPeripheralConnection(",
            "retrievePeripherals(",
            "discoverServices(",
            "discoverCharacteristics(",
            "setNotifyValue(",
            ".writeValue(",
            "writeCharacteristic(",
            "activateSensor(",
            "bindAccountOnSensor(",
            "resetSensor(",
            "writeSecretKey(",
            "CBCentralManagerOptionRestoreIdentifierKey",
        ):
            if forbidden in body:
                error(f"scan-only provisioning adapter contains forbidden surface: {forbidden}")

    active_material = ROOT / "Sources/GS3Protocol/V3ActiveSessionMaterial.swift"
    if not active_material.is_file():
        error("missing opaque active-session material boundary")
    else:
        body = active_material.read_text(encoding="utf-8", errors="replace")
        for required in (
            "package func authenticationFrame()",
            "package func effectiveDataFrame(",
            "package func decodeControl(",
            "package func decodeGlucose(",
            "CustomReflectable",
        ):
            if required not in body:
                error(f"active-session material missing boundary: {required}")
        for forbidden in (
            "public func authenticationFrame(",
            "public func effectiveDataFrame(",
            "public func decodeControl(",
            "public func decodeGlucose(",
            "import CoreBluetooth",
        ):
            if forbidden in body:
                error(f"active-session material exposes forbidden surface: {forbidden}")

    probe_machine = ROOT / "Sources/GS3DeveloperProbe/V3DeveloperHandoverProbe.swift"
    if not probe_machine.is_file():
        error("missing typed developer-probe state machine")
    else:
        machine_body = probe_machine.read_text(encoding="utf-8", errors="replace")
        for required in (
            "V3ProbePacketDiagnostic",
            "V3ProbeInboundClassification",
            "LocalizedError",
            "case unexpectedNotification(V3ProbePacketDiagnostic)",
            '"RX FF31: \\(classification), \\(byteCount) bytes; "',
            "case glucoseDeclaredLengthMismatch",
            "case quarantinedGlucoseCommand(UInt8)",
            "case glucoseRecordLayoutMismatch",
            "case glucoseChecksumMismatch",
            "effectiveDataWriteAcknowledgementPending",
            "frame.byteCount == 24",
            "quarantinedGlucoseCommandCount == 0",
            "completionGatePassed",
        ):
            if required not in machine_body:
                error(f"developer probe missing redacted diagnostic boundary: {required}")

    disconnect_diagnostic = (
        ROOT / "Sources/GS3DeveloperProbe/V3ProbeDisconnectDiagnostic.swift"
    )
    if not disconnect_diagnostic.is_file():
        error("missing payload-free developer-probe disconnect diagnostic")
    else:
        diagnostic_body = disconnect_diagnostic.read_text(
            encoding="utf-8", errors="replace"
        )
        for required in (
            "case coreBluetooth(code: Int)",
            "case redactedOther",
            "elapsedWholeSeconds",
            "authenticationWriteCallCount",
            "effectiveDataWriteCallCount",
            "uniqueLiveReadingCount",
            "quarantinedCommandCount",
            "failureDescription",
        ):
            if required not in diagnostic_body:
                error(
                    "developer probe missing disconnect diagnostic boundary: "
                    + required
                )

    package_text = (ROOT / "Package.swift").read_text(encoding="utf-8", errors="replace")
    project_text = (ROOT / "project.yml").read_text(encoding="utf-8", errors="replace")
    if '.library(name: "GS3DeveloperProbe"' not in package_text:
        error("typed developer probe must be a separate Swift package product")
    if "  SugarmanProbe:\n" not in project_text:
        error("typed developer probe must be a separate Xcode application target")
    else:
        main_target = project_text.split("  Sugarman:\n", 1)[1].split(
            "  SugarmanProbe:\n", 1
        )[0]
        if "GS3DeveloperProbe" in main_target or "Apps/SugarmanProbe" in main_target:
            error("App Store Sugarman target must not link the developer probe")
    variant_path = ROOT / "Sources/SugarmanDomain/ProtocolVariant.swift"
    variant_text = variant_path.read_text(encoding="utf-8", errors="replace")
    if re.search(r"\bcase\s+v3AES\b", variant_text):
        source_map = ROOT / "docs/V3_AUTH_SOURCE_MAP_2026-08-30.md"
        if not source_map.is_file():
            error("ProtocolVariant v3AES requires the owned-binary source map")
        registry = json.loads(
            (ROOT / "docs/provenance/registry.json").read_text(encoding="utf-8")
        )
        record = next(
            (
                item
                for item in registry.get("records", [])
                if item.get("id") == "prov-20260830-v3-offline-auth-codec"
            ),
            None,
        )
        if record is None:
            error("ProtocolVariant v3AES requires an exact provenance record")
        elif record.get("legal_review_status") not in {
            "lean-local",
            "distribution-approved",
        }:
            error("ProtocolVariant v3AES requires recorded scoped legal review")


def check_sensor_ownership_and_foreground_slice() -> None:
    group = "group.app.sugarman.sensor-owner"
    project = (ROOT / "project.yml").read_text(encoding="utf-8", errors="replace")
    if project.count(group) != 4:
        error("all iOS and macOS sensor targets must declare the sensor-owner App Group")
    if project.count("product: SensorOwnership") != 4:
        error("all iOS and macOS sensor targets must link SensorOwnership")

    for relative in (
        "Apps/Sugarman/Sugarman.entitlements",
        "Apps/SugarmanDeviceTest/SugarmanDeviceTest.entitlements",
        "Apps/SugarmanProbe/SugarmanProbe.entitlements",
        "Apps/SugarmanMacDeviceTest/SugarmanMacDeviceTest.entitlements",
    ):
        path = ROOT / relative
        if not path.is_file() or group not in path.read_text(
            encoding="utf-8", errors="replace"
        ):
            error(f"{relative} missing shared sensor-owner App Group")

    ownership = ROOT / "Sources/SensorOwnership/SensorOwnerLease.swift"
    if not ownership.is_file():
        error("missing cross-process sensor ownership lease")
    else:
        body = ownership.read_text(encoding="utf-8", errors="replace")
        for required in (
            '@_silgen_name("flock")',
            "LOCK_EX | LOCK_NB",
            "O_CLOEXEC",
            "O_NOFOLLOW",
            "alreadyOwnedByAnotherProcess",
            "SharedSensorOwnerLease",
        ):
            if required not in body:
                error(f"sensor ownership lease missing boundary: {required}")
        if re.search(r"\b(write|pwrite)\s*\(", body):
            error("sensor ownership lock file must remain payload-free")

    for relative in (
        "Apps/Sugarman/DiagnosticProbeSession.swift",
        "Sources/GS3DeviceTesting/GS3ProbeProvisioningScanner.swift",
        "Apps/SugarmanProbe/V3ProbeBluetoothRuntime.swift",
    ):
        path = ROOT / relative
        body = path.read_text(encoding="utf-8", errors="replace")
        if "SharedSensorOwnerLease.acquire()" not in body:
            error(f"{relative} bypasses shared sensor ownership")

    session_root = ROOT / "Sources/GS3Session"
    if not session_root.is_dir():
        error("missing host-testable foreground GS3 session slice")
        return
    session_body = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in sorted(session_root.glob("*.swift"))
    )
    for required in (
        "GS3ForegroundSessionMachine",
        "acquireOwnership",
        "subscribeToNotifications",
        "authenticateConnection",
        "prepareHistoryRequest",
        "requestHistory",
        "scheduleReconnect",
        "persistenceFailed",
        "CaptureBackedHistoryStart",
        "HistoryCursorPolicy",
        "GS3LifecycleEvent",
        "historyPreambleObserved",
        "historyPreambleCount",
    ):
        if required not in session_body:
            error(f"foreground GS3 slice missing boundary: {required}")
    for forbidden in (
        ".writeValue(",
        "import CoreBluetooth",
        "import GS3Protocol",
        "Data(",
        "[UInt8]",
        "EncodedFrame(bytes:",
        "activateSensor(",
        "resetSensor(",
        "writeSecretKey(",
    ):
        if forbidden in session_body:
            error(f"foreground GS3 slice contains forbidden live surface: {forbidden}")

    transport_root = ROOT / "Sources/GS3Transport"
    production_body = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in sorted(transport_root.glob("GS3Foreground*.swift"))
    )
    for required in (
        "SharedGS3SensorOwnershipProvider()",
        "SharedSensorOwnerLease.acquire()",
        "package func receive(_ event: GS3ForegroundTransportEvent)",
        "establishingTimeAnchor:",
        "inferredTimeMappingRevision",
        "validateDurableTimeline(for: session)",
        "store.setConnection(",
        "foregroundStopRequested",
        "effectStartsNewForegroundWork(",
        "bufferingPolicy: .bufferingOldest(256)",
        "for await event in events",
        "case .dropped:",
        "clearBufferedRecordsOnSuccess: true",
        "UInt16(exactly: plan.startingIndex)",
        "quality: .questionable",
        "case .historyPreambleObserved:",
    ):
        if required not in production_body:
            error(f"foreground production integration missing boundary: {required}")

    inbound_classifier = transport_root / "V3ForegroundInboundClassifier.swift"
    if not inbound_classifier.is_file():
        error("missing host-testable foreground inbound classifier")
    else:
        classifier_body = inbound_classifier.read_text(
            encoding="utf-8", errors="replace"
        )
        for required in (
            "observedHistoryPreambleCommand: UInt8 = 0x36",
            "observedHistoryPreambleByteCount = 24",
            "historyWriteAcknowledgementPending",
            "historyWriteCallCount == 1",
            "!hasReceivedGlucoseBatch",
            "historyPreambleCount == 0",
            "case observedHistoryPreamble",
            "throw error",
        ):
            if required not in classifier_body:
                error(f"foreground inbound classifier missing boundary: {required}")
        for forbidden in (
            ".writeValue(",
            "requestEffectiveData(",
            "connectKnownPeripheral(",
            "scanForPeripherals(",
        ):
            if forbidden in classifier_body:
                error(f"foreground inbound classifier contains live surface: {forbidden}")

    core_bluetooth_path = transport_root / "GS3ForegroundCoreBluetoothTransport.swift"
    core_bluetooth_body = core_bluetooth_path.read_text(
        encoding="utf-8", errors="replace"
    )
    for required in (
        "V3ForegroundInboundClassifier.classify(",
        "inFlightCommand == .effectiveData",
        "historyPreambleCount = 1",
        "emit(.historyPreambleObserved)",
    ):
        if required not in core_bluetooth_body:
            error(f"foreground CoreBluetooth preamble boundary missing: {required}")

    coordinator_path = transport_root / "GS3ForegroundSessionCoordinator.swift"
    coordinator_body = coordinator_path.read_text(encoding="utf-8", errors="replace")
    if "public init(" in coordinator_body:
        error("foreground coordinator construction must remain package-scoped")
    if coordinator_body.count("package init(") < 2:
        error("foreground coordinator test injection must remain package-scoped")
    if "quality: .ok" in coordinator_body:
        error("unverified V3 state flags must not produce current-quality samples")
    for required in (
        "GS3ForegroundSessionCoordinator(state: redacted)",
        "CustomDebugStringConvertible, CustomReflectable",
    ):
        if required not in coordinator_body:
            error(f"foreground coordinator diagnostics missing redaction: {required}")

    foreground_api_body = (
        transport_root / "GS3ForegroundTransport.swift"
    ).read_text(encoding="utf-8", errors="replace")
    for required in (
        "CustomDebugStringConvertible, CustomReflectable",
        'children: ["event": description]',
    ):
        if required not in foreground_api_body:
            error(f"foreground transport diagnostics missing redaction: {required}")

    anchor_path = ROOT / "Sources/SugarmanDomain/SensorTimeAnchor.swift"
    anchor_body = anchor_path.read_text(encoding="utf-8", errors="replace")
    for required in (
        "sampleIntervalSeconds: TimeInterval",
        "mappingRevision: String",
        "public init(from decoder: any Decoder) throws",
        '"sampleIntervalSeconds": "redacted"',
        '"mappingRevision": "redacted"',
    ):
        if required not in anchor_body:
            error(f"durable time anchor missing boundary: {required}")

    app = ROOT / "Apps/Sugarman/SugarmanApp.swift"
    bridge = ROOT / "Sources/GS3Transport/GS3ForegroundSessionLifecycle.swift"
    if not bridge.is_file():
        error("missing normal-app foreground session bridge")
    else:
        bridge_body = bridge.read_text(encoding="utf-8", errors="replace")
        for required in (
            "private var factory: Factory?",
            "func enterForeground() async throws",
            "func leaveForeground() async",
            "await starting.controller.foregroundEnded()",
            "await active.controller.foregroundEnded()",
            "await controller.foregroundEnded()",
        ):
            if required not in bridge_body:
                error(f"normal-app foreground bridge missing boundary: {required}")
        for forbidden in (
            "V3ActiveSessionMaterial(",
            "GS3ForegroundCoreBluetoothTransport(",
            "import CoreBluetooth",
        ):
            if forbidden in bridge_body:
                error(f"normal-app foreground bridge contains provisioned live surface: {forbidden}")

    app_body = app.read_text(encoding="utf-8", errors="replace")
    if app_body.count("installForegroundSessionFactory(") != 1:
        error("normal app must retain exactly one typed factory-install method")
    if (
        "#if SUGARMAN_DEVICE_TEST\n"
        "import GS3DeviceProvisioning\n"
        "import GS3DeviceTesting\n"
        "import PrivateDocumentImport\n"
        "#endif"
    ) not in app_body:
        error("device-test provisioning import must remain compile-time guarded")
    report_slice = app_body.split("var redactedDeviceTestReport: String", 1)
    if len(report_slice) != 2:
        error("missing payload-free device-test report boundary")
    else:
        report_body = report_slice[1].split(
            "func refreshDeviceTestProvisioningAvailability()", 1
        )[0]
        if "deviceTestStatus" in report_body:
            error("shareable device-test report must not include arbitrary UI status")
    import_slice = app_body.split("func importDeviceTestProvisioning(", 1)
    arm_slice = app_body.split("func armDeviceTest()", 1)
    if len(import_slice) != 2 or len(arm_slice) != 2:
        error("missing explicit device-test import and arm boundaries")
    else:
        inert_import_body = import_slice[1].split("func armDeviceTest()", 1)[0]
        for forbidden in (
            "installForegroundSessionFactory(",
            "enterForeground()",
            "makeController(",
        ):
            if forbidden in inert_import_body:
                error(f"private import must remain Bluetooth-inert: {forbidden}")
        arm_body = arm_slice[1].split("func stopDeviceTest()", 1)[0]
        for required in (
            "installForegroundSessionFactory",
            "provisioning.makeController",
            "foregroundSessionBridge.enterForeground()",
        ):
            if required not in arm_body:
                error(f"explicit device-test arm boundary missing: {required}")
    main_app_body = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in sorted((ROOT / "Apps/Sugarman").glob("*.swift"))
    )
    for forbidden in (
        "V3ActiveSessionMaterial(",
        "GS3ForegroundCoreBluetoothTransport(",
        "GS3ForegroundSessionFactory.makeKnownPeripheralController(",
    ):
        if forbidden in main_app_body:
            error(f"normal-app release sources provision forbidden live surface: {forbidden}")

    release_target = project.split("  Sugarman:\n", 1)[1].split(
        "  SugarmanDeviceTest:\n", 1
    )[0]
    device_test_target = project.split("  SugarmanDeviceTest:\n", 1)[1].split(
        "  SugarmanProbe:\n", 1
    )[0]
    if "GS3DeviceProvisioning" in release_target:
        error("release Sugarman target must not link device-only provisioning")
    if "GS3DeviceTesting" in release_target:
        error("release Sugarman target must not link device-test execution surfaces")
    if "PrivateDocumentImport" in release_target:
        error("release Sugarman target must not link private document importing")
    for required in (
        "product: GS3DeviceProvisioning",
        "product: GS3DeviceTesting",
        "SUGARMAN_DEVICE_TEST",
        "PRODUCT_BUNDLE_IDENTIFIER: app.sugarman.ios.devicetest",
    ):
        if required not in device_test_target:
            error(f"device-test target missing isolation boundary: {required}")

    provisioning_root = ROOT / "Sources/GS3DeviceProvisioning"
    if not provisioning_root.is_dir():
        error("missing device-only GS3 provisioning module")
    else:
        provisioning_body = "\n".join(
            path.read_text(encoding="utf-8", errors="replace")
            for path in sorted(provisioning_root.glob("*.swift"))
        )
        for required in (
            "DeviceOnlyGS3Provisioning",
            "KeychainGS3DeviceProvisioningStore",
            "kSecAttrAccessibleWhenUnlockedThisDeviceOnly",
            "kSecAttrSynchronizable",
            "query[kSecReturnData as String] = true",
            "GS3DeviceProvisioningDocument",
            "unexpectedDocumentField",
            "replacementRequiresDeletion",
            "GS3ForegroundSessionFactory.makeKnownPeripheralController(",
            "captureBackedStart: CaptureBackedHistoryStart(",
            "StoredGS3DeviceProvisioning(peripheral: redacted",
        ):
            if required not in provisioning_body:
                error(f"device-only provisioning missing boundary: {required}")
        for forbidden in (
            "import CoreBluetooth",
            ".writeValue(",
            "scanForPeripherals(",
            "activateSensor(",
            "resetSensor(",
            "writeSecretKey(",
            "bindAccountOnSensor(",
            "baseQuery(returnData:",
        ):
            if forbidden in provisioning_body:
                error(f"device-only provisioning contains forbidden surface: {forbidden}")

    package_text = (ROOT / "Package.swift").read_text(
        encoding="utf-8", errors="replace"
    )
    if '.library(name: "GS3DeviceProvisioning"' not in package_text:
        error("device-only provisioning must remain a separate package product")
    if '.library(name: "GS3DeviceTesting"' not in package_text:
        error("shared device-test execution boundaries must be a separate package product")

    mac_target = project.split("  SugarmanMacDeviceTest:\n", 1)[1]
    for required in (
        "platform: macOS",
        "PRODUCT_BUNDLE_IDENTIFIER: app.sugarman.macos.devicetest",
        "product: GS3DeviceProvisioning",
        "product: GS3DeviceTesting",
        "com.apple.security.device.bluetooth: true",
        "com.apple.security.files.user-selected.read-only: true",
    ):
        if required not in mac_target:
            error(f"macOS Device Test missing isolated safety boundary: {required}")

    private_import = ROOT / "Sources/PrivateDocumentImport/PrivateDocumentImportBuffer.swift"
    if not private_import.is_file():
        error("missing shared private document import buffer")
    else:
        private_import_body = private_import.read_text(
            encoding="utf-8", errors="replace"
        )
        for required in (
            "NSMutableData(contentsOf: url, options: [])",
            "bytesNoCopy:",
            "deallocator: .none",
            "#isolation",
            "resetBytes",
            "deinit",
        ):
            if required not in private_import_body:
                error(f"private document import buffer missing boundary: {required}")
        if "mappedIfSafe" in private_import_body:
            error("private document import buffer must not use memory-mapped storage")
    if '.library(name: "PrivateDocumentImport"' not in package_text:
        error("private document importing must remain a separate package product")
    if project.count("product: PrivateDocumentImport") != 3:
        error("only iOS Device Test, Probe, and macOS Device Test may import private documents")
    for relative in (
        "Apps/Sugarman/SugarmanApp.swift",
        "Apps/SugarmanProbe/ProbeAppModel.swift",
        "Apps/SugarmanMacDeviceTest/MacDeviceTestModel.swift",
    ):
        import_body = (ROOT / relative).read_text(encoding="utf-8", errors="replace")
        if "PrivateDocumentImportBuffer" not in import_body:
            error(f"private JSON importer missing owned buffer: {relative}")
        if "mappedIfSafe" in import_body:
            error(f"private JSON importer must not map files: {relative}")

    device_test_view = ROOT / "Apps/Sugarman/DeviceTestProvisioningSection.swift"
    if not device_test_view.is_file():
        error("missing compile-time guarded device-test provisioning UI")
    else:
        view_body = device_test_view.read_text(encoding="utf-8", errors="replace")
        for required in (
            "#if SUGARMAN_DEVICE_TEST",
            "Importing material does not start Bluetooth",
            "Use existing Sugarman Probe JSON",
            "Scan only; do not connect",
            "showArmConfirmation",
            "Arm managed foreground test",
            "Share redacted lifecycle report",
        ):
            if required not in view_body:
                error(f"device-test UI missing explicit safety boundary: {required}")

    mac_model = ROOT / "Apps/SugarmanMacDeviceTest/MacDeviceTestModel.swift"
    mac_view = ROOT / "Apps/SugarmanMacDeviceTest/MacDeviceTestView.swift"
    if not mac_model.is_file() or not mac_view.is_file():
        error("missing isolated macOS Device Test application shell")
    else:
        mac_body = mac_model.read_text(encoding="utf-8", errors="replace")
        mac_ui = mac_view.read_text(encoding="utf-8", errors="replace")
        for required in (
            "GS3DeviceTestExternalOwnershipGate",
            "confirmAndRunProbeBridgeScan()",
            "confirmAndArm()",
            "GS3ForegroundSessionLifecycle",
            "provisioning.makeController(",
            "PrivateDocumentImportBuffer",
            "maximumLifecycleLineCount = 128",
        ):
            if required not in mac_body:
                error(f"macOS Device Test model missing safety boundary: {required}")
        redacted_report_body = mac_body.split("var redactedReport: String", 1)[1].split(
            "func prepare()", 1
        )[0]
        if "status" in redacted_report_body:
            error("macOS redacted report must not include free-form UI status text")
        for required in (
            "CoreBluetooth identifiers are local to each host",
            "Confirm release and scan only",
            "Confirm release, arm, and connect",
            "Share redacted report",
        ):
            if required not in mac_ui:
                error(f"macOS Device Test UI missing explicit gate: {required}")

def check_private_evidence_gitignore() -> None:
    gi = ROOT / ".gitignore"
    if not gi.is_file():
        error("missing .gitignore")
        return
    text = gi.read_text(encoding="utf-8", errors="replace")
    for pattern in ("private-evidence/", "*.apk", "*.so", "*.aar"):
        if pattern not in text:
            error(f".gitignore must exclude {pattern}")
    template = ROOT / "docs/P0_INVENTORY.template.md"
    if not template.is_file():
        error("missing docs/P0_INVENTORY.template.md")
    runbook = ROOT / "docs/P1_CAPTURE_RUNBOOK.md"
    if not runbook.is_file():
        error("missing docs/P1_CAPTURE_RUNBOOK.md")

    import subprocess

    listed = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=False,
        capture_output=True,
    )
    if listed.returncode == 0 and listed.stdout:
        blocked_suffixes = (".apk", ".apks", ".aab", ".so", ".aar", ".dex")
        for raw in listed.stdout.split(b"\0"):
            if not raw:
                continue
            rel = raw.decode("utf-8", errors="replace")
            lowered = rel.lower()
            if rel == "private-evidence" or rel.startswith("private-evidence/"):
                error(f"forbidden private evidence committed: {rel}")
            elif lowered.endswith(blocked_suffixes):
                error(f"forbidden private evidence committed: {rel}")

    forbidden_nfc = re.compile(r"\b(writeNDEF|NFCTagReaderSession)\b")
    for base in (
        ROOT / "Sources/SensorOnboarding",
        ROOT / "Apps/Sugarman",
    ):
        if not base.exists():
            continue
        for path in base.rglob("*.swift"):
            body = path.read_text(encoding="utf-8", errors="replace")
            if forbidden_nfc.search(body):
                error(f"NFC write/tag-command API in {path.relative_to(ROOT).as_posix()}")


def main() -> int:
    check_licence()
    check_provenance()
    check_binaries_and_resources()
    check_no_write_api()
    check_sensor_ownership_and_foreground_slice()
    check_private_evidence_gitignore()
    if ERRORS:
        print("Governance check failed:")
        for item in ERRORS:
            print(f"  - {item}")
        return 1
    print("Governance check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
