// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import AccountBinding
import SensorOnboarding
import SugarmanDomain
import SwiftUI
import UniformTypeIdentifiers
#if canImport(CoreTransferable)
import CoreTransferable
#endif
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(CoreNFC)
import CoreNFC
#endif

struct SensorOnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var packageText = ""
    @State private var ndefText = ""
    @State private var parseMessage = String(localized: "sensor.parse_idle")
    @State private var parsedIdentity: SensorIdentity?
    @State private var parsedRegion = ""
    @State private var parsedConfidence = ""
    @State private var parsedIsSynthetic = true
    @State private var ownerID = ""
    @State private var ownerStatus = String(localized: "onboarding.owner_idle")
    @State private var confirmStore = false
    @State private var showFileImporter = false
#if os(iOS) && canImport(AVFoundation) && canImport(UIKit) && canImport(Vision) && !targetEnvironment(simulator)
    @State private var showCamera = false
#endif
#if canImport(PhotosUI)
    @State private var pickerItem: PhotosPickerItem?
#endif
#if canImport(CoreNFC)
    @State private var ndefReader = CoreNFCNDEFReader()
#endif

    private let packageParser = BoundedPackageParser()
    private let ndefParser = BoundedNDEFParser()
#if canImport(Vision)
    private let imageScanner: any BarcodeImageScanning = VisionDataMatrixScanner()
#else
    private let imageScanner: any BarcodeImageScanning = StubBarcodeImageScanner()
#endif

    var body: some View {
        NavigationStack {
            Form {
                Section("sensor.hardware") {
#if os(iOS) && canImport(AVFoundation) && canImport(UIKit) && canImport(Vision) && !targetEnvironment(simulator)
                    Button {
                        showCamera = true
                    } label: {
                        Label("sensor.camera_scan", systemImage: "camera.viewfinder")
                    }
                    .accessibilityLabel(Text("sensor.camera_scan"))
                    .accessibilityHint(Text("sensor.camera_scan_hint"))
#else
                    Text("sensor.camera_unavailable")
#endif
#if canImport(CoreNFC)
                    if NFCNDEFReaderSession.readingAvailable {
                        Button {
                            Task { await scanNDEF() }
                        } label: {
                            Label("sensor.nfc_scan", systemImage: "wave.3.right")
                        }
                        .accessibilityLabel(Text("sensor.nfc_scan"))
                        .accessibilityHint(Text("sensor.nfc_scan_hint"))
                    } else {
                        Text("sensor.nfc_unavailable")
                    }
#else
                    Text("sensor.nfc_unavailable")
#endif
#if canImport(PhotosUI)
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("sensor.import_image", systemImage: "photo")
                    }
                    .accessibilityLabel(Text("sensor.import_image"))
                    .accessibilityHint(Text("sensor.import_image_hint"))
#endif
                    Button("sensor.import_file") {
                        showFileImporter = true
                    }
                    .accessibilityLabel(Text("sensor.import_file"))
                    .accessibilityHint(Text("sensor.import_file_hint"))
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
                        Text(parsedIsSynthetic ? "sensor.synthetic_notice" : "sensor.owned_hardware_notice")
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
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task { await importFile(url) }
                    }
                case .failure(let error):
                    parseMessage = error.localizedDescription
                }
            }
#if canImport(PhotosUI)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await importPickerItem(item) }
            }
#endif
#if os(iOS) && canImport(AVFoundation) && canImport(UIKit) && canImport(Vision) && !targetEnvironment(simulator)
            .fullScreenCover(isPresented: $showCamera) {
                DataMatrixCameraView(
                    onPayload: { payload in
                        showCamera = false
                        packageText = payload
                        applyParsedPackage(payload, ndef: ndefText)
                    },
                    onCancel: {
                        showCamera = false
                    }
                )
                .ignoresSafeArea()
            }
#endif
        }
    }

    private func parsePayloads() {
        applyParsedPackage(packageText, ndef: ndefText)
    }

#if canImport(CoreNFC)
    private func scanNDEF() async {
        do {
            let records = try await ndefReader.readTextRecords()
            let joined = records.joined(separator: "\n")
            ndefText = joined
            applyParsedPackage(packageText, ndef: joined)
        } catch {
            parseMessage = error.localizedDescription
        }
    }
#endif

    private func applyParsedPackage(_ package: String, ndef: String) {
        parsedIdentity = nil
        do {
            if package.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && ndef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parseMessage = String(localized: "sensor.parse_idle")
                return
            }
            var productName: String?
            var sku: String?
            var gtin: String?
            var serial = "…"
            var region = String(localized: "sensor.unknown_region")
            var confidence = EvidenceConfidence.unsupported
            var protocolVariant = ProtocolVariant.unknown
            var evidenceFormats: [String] = []
            var isSynthetic = true

            if !package.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let parsed = try packageParser.parse(package)
                productName = parsed.productName
                sku = parsed.sku
                gtin = parsed.gtin
                serial = parsed.redactedSerial
                region = parsed.regionHypothesis
                confidence = parsed.confidence
                protocolVariant = parsed.protocolHypothesis
                evidenceFormats.append(parsed.formatName)
                isSynthetic = isSynthetic && parsed.isSynthetic
            }
            if !ndef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let parsed = try ndefParser.parse(ndef)
                productName = parsed.productName ?? productName
                sku = parsed.sku ?? sku
                serial = parsed.redactedSerial ?? serial
                region = parsed.regionHypothesis
                confidence = parsed.confidence
                protocolVariant = parsed.protocolHypothesis
                evidenceFormats.append(parsed.formatName)
                isSynthetic = isSynthetic && parsed.isSynthetic
            }

            parsedIdentity = SensorIdentity(
                productName: productName,
                sku: sku,
                gtin: gtin,
                redactedSerial: serial,
                protocolVariant: protocolVariant,
                classificationEvidenceRevision: evidenceFormats.joined(separator: "+")
            )
            parsedRegion = region
            parsedConfidence = confidence.rawValue
            parsedIsSynthetic = isSynthetic
            parseMessage = String(localized: "sensor.parse_ok")
        } catch {
            parseMessage = error.localizedDescription
            parsedIdentity = nil
        }
    }

    private func importImageData(_ data: Data) async {
        do {
            let payloads = try await imageScanner.payloads(fromImageData: data)
            var firstParseable: String?
            for payload in payloads {
                do {
                    _ = try packageParser.parse(payload)
                    firstParseable = payload
                    break
                } catch {
                    continue
                }
            }
            guard let first = firstParseable else {
                parseMessage = String(localized: "sensor.no_barcode")
                parsedIdentity = nil
                return
            }
            packageText = first
            applyParsedPackage(first, ndef: "")
        } catch {
            parseMessage = error.localizedDescription
            parsedIdentity = nil
        }
    }

#if canImport(PhotosUI)
    private func importPickerItem(_ item: PhotosPickerItem) async {
        do {
            if let picked = try await item.loadTransferable(type: PickedImageData.self) {
                await importImageData(picked.data)
                return
            }
            parseMessage = String(localized: "sensor.no_barcode")
        } catch {
            parseMessage = error.localizedDescription
        }
    }
#endif

    private func importFile(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            await importImageData(data)
        } catch {
            parseMessage = error.localizedDescription
        }
    }

    private func storeParsedIdentity() async {
        guard let parsedIdentity else { return }
        do {
            try await model.confirmIdentity(parsedIdentity)
            parseMessage = String(localized: "sensor.stored_ok")
            self.parsedIdentity = nil
        } catch {
            parseMessage = error.localizedDescription
        }
    }
}

private struct PickedImageData: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PickedImageData(data: data)
        }
    }
}
