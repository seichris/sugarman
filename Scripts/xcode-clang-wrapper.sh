#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Sugarman contributors

set -euo pipefail

sugarman_developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
sugarman_clang="${sugarman_developer_dir}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"

if [[ ! -x "${sugarman_clang}" ]]; then
    echo "Apple clang is unavailable at ${sugarman_clang}" >&2
    exit 69
fi

sugarman_is_preprocess=false
sugarman_is_macro_dump=false
sugarman_has_null_input=false

for argument in "$@"; do
    case "${argument}" in
        -E) sugarman_is_preprocess=true ;;
        -dM) sugarman_is_macro_dump=true ;;
        /dev/null) sugarman_has_null_input=true ;;
    esac
done

# Xcode 26.6's build service can block while capturing verbose stderr from its
# compiler-discovery probe. Remove only `-v` from that probe. Every real
# compiler/link invocation is forwarded byte-for-byte to Apple clang.
if ${sugarman_is_preprocess} && ${sugarman_is_macro_dump} && ${sugarman_has_null_input}; then
    sugarman_filtered_arguments=()
    for argument in "$@"; do
        if [[ "${argument}" != "-v" ]]; then
            sugarman_filtered_arguments+=("${argument}")
        fi
    done
    exec "${sugarman_clang}" "${sugarman_filtered_arguments[@]}"
fi

exec "${sugarman_clang}" "$@"
