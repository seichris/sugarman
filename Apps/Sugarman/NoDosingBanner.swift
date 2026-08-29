// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain
import SwiftUI

struct NoDosingBanner: View {
    var body: some View {
        Text(verbatim: ProductCopy.noDosing)
            .font(.footnote)
            .foregroundStyle(.primary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.orange.opacity(0.55), lineWidth: 1)
            )
            .accessibilityLabel(Text(verbatim: ProductCopy.noDosing))
            .accessibilityAddTraits(.isHeader)
    }
}

struct SyntheticDemoBanner: View {
    var body: some View {
        Text(verbatim: ProductCopy.syntheticDemo)
            .font(.footnote)
            .bold()
            .foregroundStyle(.primary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.yellow.opacity(0.8), lineWidth: 1)
            )
            .accessibilityLabel(Text(verbatim: ProductCopy.syntheticDemo))
    }
}
