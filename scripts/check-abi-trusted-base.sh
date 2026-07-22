#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# check-abi-trusted-base.sh — what the Idris2 ABI is allowed to assume.
#
# `idris2 --typecheck` passing does NOT mean the ABI proves anything. A module
# can typecheck while cheating:
#
#   believe_me         coerces between any two types — the universal escape
#   assert_total       silences the totality checker for one expression
#   assert_smaller     asserts a recursive argument decreases when it may not
#   idris_crash        a well-typed hole that aborts at runtime
#   unsafePerformIO    smuggles effects into a "pure" extractor
#   %default partial   turns off totality checking for a whole module
#
# The estate has been bitten by exactly this shape before: a Lean project's
# `sorry` gate was green while sixteen results were stubbed as `axiom`,
# including a vacuous soundness theorem. "It builds" is not "it is proved".
#
# This script states the ABI's trusted base explicitly and fails if anything
# widens it. It does NOT typecheck — `just typecheck-abi` does that; this
# checks what the typechecker is not asked to notice.
set -euo pipefail

cd "$(dirname "$0")/.."

ABI_DIR=abi
# The ABI is exactly what idaptik-ums.ipkg declares. abi/ExtractorsTest.idr
# also lives here but belongs to extractors-test.ipkg — it is a test harness,
# not part of the proved surface, so it is deliberately out of scope.
EXPECTED_MODULES=17

rc=0

# --- 1. The package manifest is the source of truth for what is checked -----
mapfile -t MODULES < <(sed -n '/^modules/,/^depends/p' idaptik-ums.ipkg \
    | tr ',' '\n' | sed 's/modules *= *//' \
    | grep -oE '^\s*[A-Z][A-Za-z0-9]*\s*$' | tr -d ' ')

declared=${#MODULES[@]}
if [ "$declared" -ne "$EXPECTED_MODULES" ]; then
    echo "::error::idaptik-ums.ipkg declares $declared modules, expected $EXPECTED_MODULES"
    rc=1
fi

# Every declared module must have a file. A module listed but absent would
# make `idris2 --typecheck` fail anyway; a file present but UNLISTED would
# silently escape every check below, which is the case worth catching.
FILES=()
for m in "${MODULES[@]}"; do
    f="$ABI_DIR/$m.idr"
    if [ ! -f "$f" ]; then
        echo "::error::idaptik-ums.ipkg declares $m but $f does not exist"
        rc=1
    else
        FILES+=("$f")
    fi
done

for f in "$ABI_DIR"/*.idr; do
    base=$(basename "$f" .idr)
    case " ${MODULES[*]} " in
        *" $base "*) ;;
        *)
            # Known, deliberate exception: the extractor test harness.
            [ "$base" = "ExtractorsTest" ] && continue
            echo "::error::$f is not declared in idaptik-ums.ipkg, so nothing checks it"
            rc=1
            ;;
    esac
done
[ "$rc" -eq 0 ] && echo "modules:        $declared declared, all present and checked"

# --- 2. No escape hatches ---------------------------------------------------
for pattern in believe_me assert_total assert_smaller idris_crash unsafePerformIO postulate; do
    # Ignore comment lines: this file's own rationale may name them, and so
    # may a module's docs. Only real uses count.
    hits=$(grep -nE "(^|[^-])\b${pattern}\b" "${FILES[@]}" 2>/dev/null \
        | grep -vE '^\S+:[0-9]+:\s*--' || true)
    if [ -n "$hits" ]; then
        echo "::error::$pattern widens the ABI's trusted base:"
        echo "$hits" | sed 's/^/    /'
        rc=1
    fi
done
[ "$rc" -eq 0 ] && echo "escape hatches: none (believe_me, assert_total, assert_smaller, idris_crash, unsafePerformIO, postulate)"

# --- 3. Every module is totality-checked ------------------------------------
missing_total=""
for f in "${FILES[@]}"; do
    grep -q '^%default total' "$f" || missing_total="$missing_total $f"
done
if [ -n "$missing_total" ]; then
    echo "::error::modules without '%default total':$missing_total"
    rc=1
fi
if grep -n '^%default partial' "${FILES[@]}" 2>/dev/null; then
    echo "::error::'%default partial' disables totality checking for a whole module"
    rc=1
fi
[ "$rc" -eq 0 ] && echo "totality:       all $EXPECTED_MODULES modules declare %default total"

if [ "$rc" -eq 0 ]; then
    echo
    echo "ABI trusted base is clean: $declared total modules, no escape hatches."
fi
exit $rc
