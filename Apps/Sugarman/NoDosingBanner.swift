// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain
import SwiftUI

struct NoDosingBanner: View {
    var body: some View {
        Text(verbatim: ProductCopy.noDosing)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(Text(verbatim: ProductCopy.noDosing))
    }
}

struct SyntheticDemoBanner: View {
    var body: some View {
        Text(verbatim: ProductCopy.syntheticDemo)
            .font(.footnote)
            .bold()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(Text(verbatim: ProductCopy.syntheticDemo))
    }
}
