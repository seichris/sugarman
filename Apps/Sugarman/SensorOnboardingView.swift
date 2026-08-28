// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import AccountBinding
import SensorOnboarding
import SugarmanDomain
import SwiftUI

struct SensorOnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var packageText = ""
    @State private var ndefText = ""
    @State private var parseMessage = String(localized: "sensor.parse_idle")
    @State private var parsedIdentity: SensorIdentity?
    @State private var parsedRegion = ""
    @State private var parsedConfidence = ""
    @State private var ownerID = ""
    @State private var ownerStatus = String(localized: "onboarding.owner_idle")
    @State private var confirmStore = false

    private let packageParser = BoundedPackageParser()
    private let ndefParser = BoundedNDEFParser()

    var body: some View {
        NavigationStack {
            Form {
                Section("sensor.hardware") {
                    Text("sensor.camera_unavailable")
                    Text("sensor.nfc_unavailable")
                    Text("onboarding.no_commands")
                        .foregroundStyle(.secondary)
                }
                Section("sensor.package") {
                    TextField("sensor.package_field", text: $packageText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(3...8)
                    TextField("sensor.ndef_field", text: $ndefText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(2...6)
                    Button("sensor.parse") {
                        parsePayloads()
                    }
                    Text(parseMessage)
                        .font(.footnote)
                }
                if let identity = parsedIdentity {
                    Section("sensor.parsed") {
                        LabeledContent("sensor.product", value: identity.productName ?? String(localized: "sensor.unknown_product"))
                        LabeledContent("sensor.sku", value: identity.sku ?? String(localized: "sensor.unknown_sku"))
                        LabeledContent("sensor.serial", value: identity.redactedSerial)
                        LabeledContent("sensor.region", value: parsedRegion)
                        LabeledContent("sensor.protocol", value: identity.protocolVariant.rawValue)
                        LabeledContent("sensor.confidence", value: parsedConfidence)
                        Text("sensor.synthetic_notice")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("sensor.confirm") {
                            confirmStore = true
                        }
                        .accessibilityHint(Text("sensor.confirm_hint"))
                    }
                }
                Section("sensor.stored") {
                    if model.identities.isEmpty {
                        Text("sensor.no_identity")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.identities) { identity in
                            VStack(alignment: .leading) {
                                Text(identity.productName ?? String(localized: "sensor.unknown_product"))
                                Text(identity.redactedSerial)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                Section("onboarding.owner") {
                    TextField("onboarding.owner_field", text: $ownerID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("onboarding.owner_save") {
                        do {
                            let id = try model.storeOwnerAccountID(ownerID)
                            ownerStatus = String(
                                format: String(localized: "onboarding.owner_ok"),
                                locale: .current,
                                id.value
                            )
                        } catch {
                            ownerStatus = error.localizedDescription
                        }
                    }
                    Text(ownerStatus)
                        .font(.footnote)
                    Text("onboarding.no_email")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("sensor.title")
            .confirmationDialog("sensor.confirm_title", isPresented: $confirmStore) {
                Button("sensor.confirm") {
                    Task { await storeParsedIdentity() }
                }
            } message: {
                Text("sensor.confirm_body")
            }
        }
    }

    private func parsePayloads() {
        parsedIdentity = nil
        do {
            if packageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && ndefText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parseMessage = String(localized: "sensor.parse_idle")
                return
            }
            var productName: String?
            var sku: String?
            var gtin: String?
            var serial = "…"
            var region = String(localized: "sensor.unknown_region")
            var confidence = EvidenceConfidence.unsupported

            if !packageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let package = try packageParser.parse(packageText)
                productName = package.productName
                sku = package.sku
                gtin = package.gtin
                serial = package.redactedSerial
                region = package.regionHypothesis
                confidence = package.confidence
            }
            if !ndefText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let ndef = try ndefParser.parse(ndefText)
                productName = ndef.productName ?? productName
                sku = ndef.sku ?? sku
                serial = ndef.redactedSerial ?? serial
                region = ndef.regionHypothesis
                confidence = ndef.confidence
            }

            parsedIdentity = SensorIdentity(
                productName: productName,
                sku: sku,
                gtin: gtin,
                redactedSerial: serial,
                protocolVariant: .unknown,
                classificationEvidenceRevision: "synthetic-demo"
            )
            parsedRegion = region
            parsedConfidence = confidence.rawValue
            parseMessage = String(localized: "sensor.parse_ok")
        } catch {
            parseMessage = error.localizedDescription
            parsedIdentity = nil
        }
    }

    private func storeParsedIdentity() async {
        guard let parsedIdentity else { return }
        await model.confirmIdentity(parsedIdentity)
        parseMessage = String(localized: "sensor.stored_ok")
        self.parsedIdentity = nil
    }
}
