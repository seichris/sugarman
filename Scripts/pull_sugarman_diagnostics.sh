#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Sugarman contributors

set -euo pipefail

if (( $# != 2 )); then
    print "usage: $0 <core-device-id-or-udid> <output-file>" >&2
    exit 2
fi

device="$1"
destination="$2"
if [[ -z "$device" || -z "$destination" ]]; then
    print "device and output-file must not be empty" >&2
    exit 2
fi

destination_directory="${destination:h}"
if [[ -z "$destination_directory" || "$destination_directory" == "$destination" ]]; then
    destination_directory="."
fi
mkdir -p -- "$destination_directory"

xcrun devicectl device copy from \
    --device "$device" \
    --domain-type appDataContainer \
    --domain-identifier app.sugarman.ios \
    --source 'Library/Application Support/Sugarman/diagnostics.jsonl' \
    --destination "$destination"

print "Copied Sugarman diagnostics to $destination"
