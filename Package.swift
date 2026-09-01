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
        .library(name: "GS3Session", targets: ["GS3Session"]),
        .library(name: "GS3DeviceProvisioning", targets: ["GS3DeviceProvisioning"]),
        .library(name: "GS3ProvisioningScan", targets: ["GS3ProvisioningScan"]),
        .library(name: "GS3DeviceTesting", targets: ["GS3DeviceTesting"]),
        .library(name: "GS3DeveloperProbe", targets: ["GS3DeveloperProbe"]),
        .library(name: "PrivateDocumentImport", targets: ["PrivateDocumentImport"]),
        .library(name: "SensorOwnership", targets: ["SensorOwnership"]),
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
        .target(
            name: "GS3Transport",
            dependencies: [
                "SugarmanDomain",
                "GS3Protocol",
                "GS3Session",
                "SensorOwnership",
                "SugarmanStore",
            ]
        ),
        .target(
            name: "GS3Session",
            dependencies: ["SugarmanDomain", "SugarmanStore"]
        ),
        .target(
            name: "GS3DeviceProvisioning",
            dependencies: [
                "GS3Protocol",
                "GS3Session",
                "GS3Transport",
                "SugarmanDomain",
                "SugarmanStore",
            ],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .target(
            name: "GS3ProvisioningScan",
            dependencies: [
                "GS3DeviceProvisioning",
                "SensorOwnership",
            ],
            linkerSettings: [.linkedFramework("CoreBluetooth")]
        ),
        .target(
            name: "GS3DeviceTesting",
            dependencies: [
                "GS3DeviceProvisioning",
                "GS3Session",
                "GS3Transport",
                "SugarmanStore",
            ]
        ),
        .target(
            name: "GS3DeveloperProbe",
            dependencies: ["GS3Protocol"],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .target(name: "PrivateDocumentImport"),
        .target(name: "SensorOwnership"),
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
        .testTarget(
            name: "GS3TransportTests",
            dependencies: [
                "GS3Transport",
                "GS3Protocol",
                "GS3Session",
                "SugarmanDomain",
                "SugarmanStore",
            ]
        ),
        .testTarget(
            name: "GS3SessionTests",
            dependencies: ["GS3Session", "SafetyEngine", "SugarmanDomain", "SugarmanStore"]
        ),
        .testTarget(
            name: "GS3DeviceProvisioningTests",
            dependencies: [
                "GS3DeviceProvisioning",
                "GS3Transport",
                "SugarmanDomain",
                "SugarmanStore",
            ]
        ),
        .testTarget(
            name: "GS3DeviceTestingTests",
            dependencies: ["GS3DeviceTesting", "GS3ProvisioningScan"]
        ),
        .testTarget(
            name: "GS3DeveloperProbeTests",
            dependencies: ["GS3DeveloperProbe", "GS3Protocol"]
        ),
        .testTarget(
            name: "PrivateDocumentImportTests",
            dependencies: ["PrivateDocumentImport"]
        ),
        .testTarget(name: "SensorOwnershipTests", dependencies: ["SensorOwnership"]),
        .testTarget(name: "SensorOnboardingTests", dependencies: ["SensorOnboarding"]),
        .testTarget(name: "AccountBindingTests", dependencies: ["AccountBinding"]),
        .testTarget(name: "SugarmanStoreTests", dependencies: ["SugarmanStore", "SugarmanDomain"]),
        .testTarget(name: "SafetyEngineTests", dependencies: ["SafetyEngine", "SugarmanDomain"]),
        .testTarget(name: "IntegrationsTests", dependencies: ["Integrations", "SugarmanDomain", "SugarmanStore"]),
        .testTarget(
            name: "SugarmanDiagnosticsTests",
            dependencies: ["SugarmanDiagnostics", "GS3Transport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
