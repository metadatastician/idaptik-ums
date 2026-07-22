#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# spark-parity.sh — the SPARK model and the Rust engine must agree.
#
# The SPARK package is a proved REFERENCE MODEL, not linked at runtime
# (ADR-0003 §3). A reference model nothing compares against is decoration, so
# this drives every vector in spark/vectors.txt through both implementations
# and diffs the verdicts.
#
# Neither side is allowed to be absent. A parity harness that skips when a
# toolchain is missing reports agreement between one implementation and
# nothing.
set -euo pipefail

cd "$(dirname "$0")/.."

VECTORS=spark/vectors.txt
ORACLE=spark/bin/ums_zones_oracle

command -v gprbuild >/dev/null 2>&1 || {
    echo "error: gprbuild not found — the SPARK model cannot be built, so parity cannot be checked." >&2
    echo "       Install GNAT (Debian: apt install gnat). Do not skip this gate." >&2
    exit 1
}
command -v cargo >/dev/null 2>&1 || {
    echo "error: cargo not found — the Rust mirror cannot be built." >&2
    exit 1
}
[ -f "$VECTORS" ] || { echo "error: $VECTORS is missing" >&2; exit 1; }

echo "building the SPARK reference model..."
gprbuild -P spark/ums_zones.gpr -q

ada_out="$(mktemp)"
rust_out="$(mktemp)"
trap 'rm -f "$ada_out" "$rust_out"' EXIT

"./$ORACLE" < "$VECTORS" > "$ada_out"
cargo run -q -p ums-ai-edit -- zones-verdicts "$VECTORS" > "$rust_out"

ada_n=$(wc -l < "$ada_out")
rust_n=$(wc -l < "$rust_out")
cases=$(grep -cvE '^\s*(#|$)' "$VECTORS")

if [ "$ada_n" -ne "$cases" ] || [ "$rust_n" -ne "$cases" ]; then
    echo "::error::verdict count mismatch: $cases vectors, SPARK produced $ada_n, Rust produced $rust_n"
    exit 1
fi
if [ "$cases" -eq 0 ]; then
    echo "::error::$VECTORS contains no vectors; this gate would pass vacuously"
    exit 1
fi

if diff -u "$ada_out" "$rust_out" > /dev/null; then
    echo "spark-parity: $cases vectors, SPARK and Rust agree on every verdict"
    exit 0
fi

echo "::error::the SPARK reference model and the Rust engine disagree"
paste -d' ' <(grep -vE '^\s*(#|$)' "$VECTORS") "$ada_out" "$rust_out" \
    | awk '$(NF-1) != $NF { print "    vector: " $1 "  spark=" $(NF-1) "  rust=" $NF }'
exit 1
