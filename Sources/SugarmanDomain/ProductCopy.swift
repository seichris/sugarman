// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

/// Canonical English product language. User-facing UI also stores these
/// strings in the English String Catalog; tests assert against this source.
public enum ProductCopy: Sendable {
    public static let athletePurpose =
        "Glucose monitoring and fueling insight for endurance athletes."

    public static let noDosing =
        "Sugarman is an athlete fueling insight tool. It does not diagnose conditions, recommend treatment, or suggest insulin or medication doses. Never use these readings to dose insulin."

    public static let notCurrentReading =
        "This is not a current reading."

    public static let disconnected =
        "Sensor disconnected. No current glucose is available."

    public static let stale =
        "Reading is stale. Do not treat it as current."

    public static let emptyDashboard =
        "No sensor session. Sugarman has not collected any glucose yet."

    public static let connectedNoData =
        "Connected, waiting for a reading. This is not current glucose."
}
