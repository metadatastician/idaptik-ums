#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# gen.sh — regenerate every artifact derived from the Nickel source of truth.
#
#   gen.sh            write the generated files into the tree
#   gen.sh --check    write to a temp dir and diff; non-zero on drift
#
# Codegen without a diff gate is a fake gate, so --check is what CI runs.
#
# This script deliberately does NOT degrade gracefully when nickel is missing.
# A generator that silently skips its work reports success for a tree it never
# looked at — the single most common fake-gate shape in this estate.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v nickel >/dev/null 2>&1; then
    echo "error: nickel not found. The generated artifacts cannot be verified." >&2
    echo "       Install it (see mise.toml) — do not skip this gate." >&2
    exit 1
fi

# source .ncl  ->  generated artifact
TARGETS=(
    "config/edit-script-schema.ncl:schemas/edit-script.schema.json"
)

mode="${1:-write}"
rc=0

for pair in "${TARGETS[@]}"; do
    src="${pair%%:*}"
    dst="${pair#*:}"

    tmp="$(mktemp)"
    nickel export "$src" --format json > "$tmp"

    if [ "$mode" = "--check" ]; then
        if ! diff -u "$dst" "$tmp" > /dev/null 2>&1; then
            echo "::error file=$dst::generated artifact is stale — run 'just gen'"
            diff -u "$dst" "$tmp" || true
            rc=1
        else
            echo "up to date: $dst"
        fi
        rm -f "$tmp"
    else
        mv "$tmp" "$dst"
        chmod 644 "$dst"
        echo "generated: $dst  (from $src)"
    fi
done

exit $rc
