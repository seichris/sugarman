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
        if "bluetooth-central" not in text:
            error(f"{plist.relative_to(ROOT)} missing bluetooth-central")


def check_no_write_api() -> None:
    forbidden = re.compile(
        r"\b(writeValue\s*\(|writeCharacteristic\s*\(|func\s+write[A-Z])"
    )
    live_cmd = re.compile(
        r"\b(activateSensor|resetSensor|writeSecretKey|authWrite|bindAccountOnSensor)\s*\("
    )
    for base in (
        ROOT / "Sources/SugarmanDiagnostics",
        ROOT / "Sources/GS3Transport",
        ROOT / "Sources/GS3Protocol",
    ):
        if not base.is_dir():
            continue
        for path in base.rglob("*.swift"):
            text = path.read_text(encoding="utf-8", errors="replace")
            rel = path.relative_to(ROOT).as_posix()
            if forbidden.search(text):
                error(f"forbidden characteristic-write API in {rel}")
            if live_cmd.search(text):
                error(f"live sensor command API in {rel}")
    protocol_sources = list((ROOT / "Sources/GS3Protocol").rglob("*.swift"))
    for path in protocol_sources:
        text = path.read_text(encoding="utf-8", errors="replace")
        if re.search(r"\bcase\s+v3AES\b", text):
            error("ProtocolVariant must not include v3AES until a source map exists")



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
