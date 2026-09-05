// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SwiftUI

struct BluetoothOffNotice: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .padding(24)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.medium, .large] : [.height(280)])
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        VStack(spacing: 16) {
            BluetoothSymbol()
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .foregroundStyle(.blue)
                .frame(width: 26, height: 40)
                .accessibilityHidden(true)
            Text("Bluetooth is off")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Turn on Bluetooth in iPhone Settings to receive sensor readings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("OK") { dismiss() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("bluetooth-off-dismiss")
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("bluetooth-off-notice")
    }
}

/// The Bluetooth rune, drawn as a vector to scale cleanly with the notice.
private struct BluetoothSymbol: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.25))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.75))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.25))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.75))
        }
    }
}

#Preview {
    BluetoothOffNotice()
}
