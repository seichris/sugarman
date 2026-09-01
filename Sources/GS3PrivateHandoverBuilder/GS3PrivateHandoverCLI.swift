// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import PrivateDocumentImport

public enum GS3PrivateHandoverCLI: Sendable {
    public static let usage = """
    Usage:
      gs3-private-handover build --capture <android-btsnoop> --user-id <numeric-id> --private-profile <profile-json> --output <handover-json>
    """

    public static func run(
        arguments: [String],
        writeStandardOutput: (String) -> Void,
        writeStandardError: (String) -> Void
    ) -> Int32 {
        do {
            let options = try parse(arguments)
            let captureBuffer: PrivateDocumentImportBuffer
            let profileBuffer: PrivateDocumentImportBuffer
            do {
                captureBuffer = try PrivateDocumentImportBuffer(contentsOf: options.capture)
                profileBuffer = try PrivateDocumentImportBuffer(contentsOf: options.profile)
            } catch {
                throw GS3PrivateHandoverError.inputUnreadable
            }
            defer {
                captureBuffer.zeroize()
                profileBuffer.zeroize()
            }
            let artifact = try captureBuffer.withData { captureData in
                try profileBuffer.withData { profileData in
                    try GS3PrivateHandoverBuilder.generate(
                        captureData: captureData,
                        ownerVisibleUserID: options.userID,
                        privateProfileData: profileData
                    )
                }
            }
            try artifact.writeAtomically(to: options.output)
            writeStandardOutput("Private handover written securely.\n")
            return 0
        } catch let error as GS3PrivateHandoverError {
            writeStandardError("Error: \(error.description)\n")
            if error == .invalidArguments {
                writeStandardError(usage + "\n")
            }
            return 1
        } catch {
            writeStandardError("Error: The private handover operation failed closed.\n")
            return 1
        }
    }

    private struct Options {
        let capture: URL
        let userID: String
        let profile: URL
        let output: URL
    }

    private static func parse(_ arguments: [String]) throws -> Options {
        guard arguments.first == "build" else {
            throw GS3PrivateHandoverError.invalidArguments
        }
        var values: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            guard ["--capture", "--user-id", "--private-profile", "--output"]
                .contains(key),
                  values[key] == nil,
                  index + 1 < arguments.count,
                  !arguments[index + 1].isEmpty else {
                throw GS3PrivateHandoverError.invalidArguments
            }
            values[key] = arguments[index + 1]
            index += 2
        }
        guard values.count == 4,
              let capture = values["--capture"],
              let userID = values["--user-id"],
              let profile = values["--private-profile"],
              let output = values["--output"] else {
            throw GS3PrivateHandoverError.invalidArguments
        }
        let captureURL = URL(fileURLWithPath: capture).standardizedFileURL
        let profileURL = URL(fileURLWithPath: profile).standardizedFileURL
        let outputURL = URL(fileURLWithPath: output).standardizedFileURL
        guard canonicalPath(outputURL) != canonicalPath(captureURL),
              canonicalPath(outputURL) != canonicalPath(profileURL) else {
            throw GS3PrivateHandoverError.invalidArguments
        }
        return Options(
            capture: captureURL,
            userID: userID,
            profile: profileURL,
            output: outputURL
        )
    }

    private static func canonicalPath(_ url: URL) -> String {
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        return parent.appendingPathComponent(url.lastPathComponent).path
    }
}
