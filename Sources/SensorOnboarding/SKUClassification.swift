// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

/// Classification labels for SKU strings documented in the Mainland GS3 plan
/// (Juggluco `sensoren.hpp` facts). This is not Mainland hardware proof and
/// is not a copy of upstream source. Provenance: behavioral, synthetic fixtures.
public enum DocumentedSKUClassification: Sendable {
    public static let knownLabels: Set<String> = ["64221", "64300"]

    public static func productName(for sku: String) -> String? {
        guard knownLabels.contains(sku) else { return nil }
        return "GS3"
    }

    public static func regionHypothesis(for sku: String) -> String {
        switch sku {
        case "64221":
            return "Unspecified region (documented SKU label 64221 only; not hardware proof)"
        case "64300":
            return "Mainland China hypothesis (documented SKU label 64300 only; not hardware proof)"
        default:
            return "Unknown region (synthetic parse; not hardware proof)"
        }
    }
}
