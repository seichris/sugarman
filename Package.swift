// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import PackageDescription

/// Sugarman portable libraries. Licence: GPL-3.0-or-later (see LICENSE).
let package = Package(
    name: "Sugarman",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "SugarmanDomain", targets: ["SugarmanDomain"]),
        .library(name: "GS3Protocol", targets: ["GS3Protocol"]),
        .library(name: "GS3Transport", targets: ["GS3Transport"]),
        .library(name: "SensorOnboarding", targets: ["SensorOnboarding"]),
        .library(name: "AccountBinding", targets: ["AccountBinding"]),
        .library(name: "SugarmanStore", targets: ["SugarmanStore"]),
        .library(name: "SafetyEngine", targets: ["SafetyEngine"]),
        .library(name: "Integrations", targets: ["Integrations"]),
        .library(name: "SugarmanDiagnostics", targets: ["SugarmanDiagnostics"]),
    ],
    targets: [
        .target(name: "SugarmanDomain"),
        .target(name: "GS3Protocol", dependencies: ["SugarmanDomain"]),
        .target(name: "GS3Transport", dependencies: ["SugarmanDomain"]),
        .target(name: "SensorOnboarding", dependencies: ["SugarmanDomain"]),
        .target(name: "AccountBinding", dependencies: ["SugarmanDomain"]),
        .target(name: "SugarmanStore", dependencies: ["SugarmanDomain"]),
        .target(name: "SafetyEngine", dependencies: ["SugarmanDomain"]),
        .target(name: "Integrations", dependencies: ["SugarmanDomain"]),
        .target(
            name: "SugarmanDiagnostics",
            dependencies: ["SugarmanDomain", "GS3Transport"]
        ),
        .testTarget(name: "SugarmanDomainTests", dependencies: ["SugarmanDomain"]),
        .testTarget(name: "GS3ProtocolTests", dependencies: ["GS3Protocol", "SugarmanDomain"]),
        .testTarget(name: "GS3TransportTests", dependencies: ["GS3Transport"]),
        .testTarget(name: "SensorOnboardingTests", dependencies: ["SensorOnboarding"]),
        .testTarget(name: "AccountBindingTests", dependencies: ["AccountBinding"]),
        .testTarget(name: "SugarmanStoreTests", dependencies: ["SugarmanStore", "SugarmanDomain"]),
        .testTarget(name: "SafetyEngineTests", dependencies: ["SafetyEngine", "SugarmanDomain"]),
        .testTarget(name: "IntegrationsTests", dependencies: ["Integrations", "SugarmanDomain"]),
        .testTarget(
            name: "SugarmanDiagnosticsTests",
            dependencies: ["SugarmanDiagnostics", "GS3Transport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
