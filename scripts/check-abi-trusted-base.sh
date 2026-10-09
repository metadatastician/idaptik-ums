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
# widens it. It does NOT typecheck: `idris2 --typecheck idaptik-ums.ipkg` does
# that, and `just proof-check-abi` runs both. This checks what the
# typechecker is not asked to notice.
set -euo pipefail

cd "$(dirname "$0")/.."

ABI_DIR=abi
# The ABI is exactly what idaptik-ums.ipkg declares. Test harnesses also live
# in abi/ (ExtractorsTest, RepresentationTest) but each belongs to its own
# *-test.ipkg — they are not part of the proved surface, so they are out of
# scope. A harness is recognised by being declared in another package, never
# by name, so an undeclared file still fails below.
EXPECTED_MODULES=19
# A module name as Idris spells it: dot-separated, each part capitalised.
# `Extra.Helper` lives at abi/Extra/Helper.idr.
MODULE_NAME_RE='^[A-Z][A-Za-z0-9_]*([.][A-Z][A-Za-z0-9_]*)*$'

rc=0

# ipkg_modules FILE — print every name in FILE's `modules` field, one per
# line, exactly as written. The field runs until the next `name =` field, and
# `--` comments are dropped. Names are not filtered here: anything that is not
# a valid module name is reported by the caller, never silently skipped.
ipkg_modules() {
    awk '
        { sub(/--.*/, "") }
        /^[a-z_]+[[:space:]]*=/ {
            infield = /^modules[[:space:]]*=/
            sub(/^modules[[:space:]]*=/, "")
        }
        infield {
            n = split($0, parts, ",")
            for (i = 1; i <= n; i++) {
                name = parts[i]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
                if (name != "") print name
            }
        }
    ' "$1"
}

# module_file NAME — the source path Idris resolves module NAME to under abi/.
module_file() {
    echo "$ABI_DIR/${1//.//}.idr"
}

# code_lines FILE — print FILE's code as FILE:LINE:TEXT, leaving out blank
# lines, `--` line comments, `|||` doc comments and `{- -}` block comments
# that start a line.
code_lines() {
    awk -v file="$1" '
        inblock { if (/-\}/) inblock = 0; next }
        /^[[:space:]]*\{-/ { if (!/-\}/) inblock = 1; next }
        /^[[:space:]]*$/ || /^[[:space:]]*(--|\|\|\|)/ { next }
        { print file ":" NR ":" $0 }
    ' "$1"
}

# --- 1. The package manifest is the source of truth for what is checked -----
mapfile -t MODULES < <(ipkg_modules idaptik-ums.ipkg)

declared=${#MODULES[@]}
if [ "$declared" -ne "$EXPECTED_MODULES" ]; then
    echo "::error::idaptik-ums.ipkg declares $declared modules, expected $EXPECTED_MODULES"
    rc=1
fi

# Every declared module must have a file. A module listed but absent would
# make `idris2 --typecheck` fail anyway; a file present but UNLISTED would
# silently escape every check below, which is the case worth catching.
declare -A DECLARED=()
FILES=()
for m in "${MODULES[@]}"; do
    if ! [[ "$m" =~ $MODULE_NAME_RE ]]; then
        echo "::error::idaptik-ums.ipkg lists '$m', which is not a module name this check can resolve"
        rc=1
        continue
    fi
    DECLARED[$m]=1
    f=$(module_file "$m")
    if [ ! -f "$f" ]; then
        echo "::error::idaptik-ums.ipkg declares $m but $f does not exist"
        rc=1
    else
        FILES+=("$f")
    fi
done
if [ "${#FILES[@]}" -eq 0 ]; then
    echo "::error::no ABI module file to check"
    exit 1
fi

# Modules declared by the other packages whose sourcedir is abi/: the test
# harnesses. Same parse as above, applied to each *-test.ipkg.
declare -A HARNESS=()
for p in *-test.ipkg; do
    [ -f "$p" ] || continue
    grep -qE '^sourcedir *= *"abi"' "$p" || continue
    while IFS= read -r m; do
        if ! [[ "$m" =~ $MODULE_NAME_RE ]]; then
            echo "::error::$p lists '$m', which is not a module name this check can resolve"
            rc=1
            continue
        fi
        HARNESS[$m]=1
    done < <(ipkg_modules "$p")
done

# Every Idris source under abi/, at any depth, must be declared somewhere.
# Literate sources are refused outright: nothing below reads them.
while IFS= read -r f; do
    rel=${f#"$ABI_DIR"/}
    m=${rel%.*}
    m=${m//\//.}
    case "$f" in
        *.lidr)
            echo "::error::$f is literate Idris, which this check does not read"
            rc=1
            continue
            ;;
    esac
    # A test harness declared by its own package is deliberately out of
    # scope; anything else has escaped every check.
    [ -n "${DECLARED[$m]:-}" ] && continue
    [ -n "${HARNESS[$m]:-}" ] && continue
    echo "::error::$f is not declared in idaptik-ums.ipkg, so nothing checks it"
    rc=1
done < <(find "$ABI_DIR" -type f \( -name '*.idr' -o -name '*.lidr' \) | sort)
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

# --- 3. Every declaration is totality-checked -------------------------------
# `%default total` only covers what comes after it, so it must precede the
# first declaration: everything but `module`, `import` and other `%`
# directives. Anything that weakens it afterwards is refused as well:
# `%default covering` or `%default partial`, and a `partial` or `covering`
# modifier on a single declaration.
missing_total=""
late_total=""
for f in "${FILES[@]}"; do
    read -r total_at first_at < <(code_lines "$f" | awk -F: '
        { text = $0; sub(/^[^:]*:[0-9]+:/, "", text) }
        text ~ /^%default[[:space:]]+total[[:space:]]*(--.*)?$/ { if (!t) t = $2; next }
        text ~ /^(module|import)[[:space:]]/ || text ~ /^%/ { next }
        { if (!d) d = $2 }
        END { print t + 0, d + 0 }')
    if [ "$total_at" -eq 0 ]; then
        missing_total="$missing_total $f"
    elif [ "$first_at" -ne 0 ] && [ "$total_at" -gt "$first_at" ]; then
        late_total="$late_total $f:$total_at (first declaration at line $first_at)"
    fi
done
if [ -n "$missing_total" ]; then
    echo "::error::modules without '%default total':$missing_total"
    rc=1
fi
if [ -n "$late_total" ]; then
    echo "::error::'%default total' after declarations it does not cover:$late_total"
    rc=1
fi
weakened=$(for f in "${FILES[@]}"; do code_lines "$f"; done | grep -wE 'partial|covering' || true)
if [ -n "$weakened" ]; then
    echo "::error::'partial' or 'covering' turns off totality checking:"
    echo "$weakened" | sed 's/^/    /'
    rc=1
fi
[ "$rc" -eq 0 ] && echo "totality:       all $declared modules declare %default total before any declaration; none opts out"

if [ "$rc" -eq 0 ]; then
    echo
    echo "ABI trusted base is clean: $declared total modules, no escape hatches."
fi
exit $rc
