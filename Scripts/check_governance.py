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
    }
    probe_adapter = ROOT / "Apps/SugarmanProbe/V3ProbeBluetoothRuntime.swift"
    for base in (ROOT / "Sources", ROOT / "Apps"):
        if not base.is_dir():
            continue
        for path in base.rglob("*.swift"):
            text = path.read_text(encoding="utf-8", errors="replace")
            rel = path.relative_to(ROOT).as_posix()
            if characteristic_write.search(text) and path != probe_adapter:
                error(f"forbidden characteristic-write API in {rel}")
            if live_cmd.search(text):
                error(f"live sensor command API in {rel}")
            if (
                "import CoreBluetooth" in text
                and not path.is_relative_to(ROOT / "Sources/GS3Transport")
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
