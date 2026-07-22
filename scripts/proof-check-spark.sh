#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# proof-check-spark.sh — discharge the ZonesOrdered verification conditions.
#
# THIS GATE MUST BE ABLE TO FAIL. The estate's single most-repeated defect is a
# `just proof-check-*` recipe that exits 0 when the prover is not installed —
# fifty-four repository roots, every one reporting a green proof gate for a
# tree no prover ever looked at. The sibling vordr repo still has the shape:
#
#     prove-spark:
#         @if [ -d src/ada ]; then cd src/ada && gnatprove ...; \
#          else echo "No Ada code yet"; fi
#
# which passes when the directory is absent. So:
#
#   * gnatprove missing            -> exit 1, loudly
#   * spark/ sources missing       -> exit 1 (never "nothing to prove, ok")
#   * any unproved check           -> exit 1
#
# and the summary is parsed rather than trusting the exit status alone,
# because gnatprove can report unproved checks and still exit 0 depending on
# how it is invoked.
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT=spark/ums_zones.gpr

if ! command -v gnatprove >/dev/null 2>&1; then
    cat >&2 <<'MSG'
error: gnatprove not found.

  The SPARK verification conditions for spark/src/ums_zones.ads have NOT been
  discharged. This gate fails rather than passing, because a proof gate that
  exits 0 without a prover certifies nothing while looking green.

  Install SPARK (Alire: `alr toolchain --select gnatprove`, or the AdaCore
  community release). Do not "fix" this by skipping it.
MSG
    exit 1
fi

[ -f "$PROJECT" ] || { echo "error: $PROJECT is missing — there is nothing to prove, which is a failure, not a pass" >&2; exit 1; }
[ -f spark/src/ums_zones.ads ] || { echo "error: spark/src/ums_zones.ads is missing" >&2; exit 1; }

echo "discharging verification conditions (gnatprove --level=2)..."
out="$(mktemp)"
trap 'rm -f "$out"' EXIT

set +e
gnatprove -P "$PROJECT" --level=2 --report=all --output=oneline 2>&1 | tee "$out"
status=${PIPESTATUS[0]}
set -e

if [ "$status" -ne 0 ]; then
    echo "::error::gnatprove exited $status"
    exit 1
fi

# Parse the summary rather than trusting the exit status: a run can report
# unproved checks without failing, depending on invocation.
if grep -qiE '(medium|high|low):|might fail|not proved|cannot prove' "$out"; then
    echo "::error::gnatprove reported unproved checks — see the output above"
    exit 1
fi

proved=$(grep -ciE 'proved|checks? (were )?proved' "$out" || true)
echo "proof-check-spark: gnatprove reported no unproved checks (${proved} summary lines matched)"
