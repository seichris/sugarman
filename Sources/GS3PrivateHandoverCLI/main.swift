// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3PrivateHandoverBuilder

private func write(_ text: String, to handle: FileHandle) {
    if let data = text.data(using: .utf8) {
        handle.write(data)
    }
}

let status = GS3PrivateHandoverCLI.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    writeStandardOutput: { write($0, to: .standardOutput) },
    writeStandardError: { write($0, to: .standardError) }
)
exit(status)
