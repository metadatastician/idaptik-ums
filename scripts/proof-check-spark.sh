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
#   * gnatprove missing                        -> exit 1, loudly
#   * spark/ sources missing                   -> exit 1 (never "nothing to prove, ok")
#   * any unproved check                       -> exit 1
#   * any justified check or pragma Assume     -> exit 1 (waved through, not proved)
#   * no proved check at all                   -> exit 1 (a run that analysed nothing)
#   * a subprogram of the model skipped        -> exit 1
#   * Zones_Ordered's postcondition not proved -> exit 1 (the deliverable itself)
#
# and the output is parsed rather than trusting the exit status alone,
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

  Install SPARK with Alire (`alr install gnatprove`, then put ~/.alire/bin on
  PATH) or use the AdaCore community release. Do not "fix" this by skipping it.
MSG
    exit 1
fi

[ -f "$PROJECT" ] || { echo "error: $PROJECT is missing — there is nothing to prove, which is a failure, not a pass" >&2; exit 1; }
[ -f spark/src/ums_zones.ads ] || { echo "error: spark/src/ums_zones.ads is missing" >&2; exit 1; }

echo "discharging verification conditions (gnatprove --level=2, forced cold)..."
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
# The summary table gnatprove writes for this project. It is read below, so it
# must be the one THIS run wrote: `-f` re-proves every unit instead of reusing
# cached results, and the previous summary is deleted first, so a run that
# writes none cannot be judged by an old one. (A timestamp comparison cannot
# do this: a fast run can stamp its file with the same time as the marker.)
SUMMARY=spark/obj/gnatprove/gnatprove.out
rm -f "$SUMMARY"

set +e
gnatprove -P "$PROJECT" -f --level=2 --report=all --output=oneline 2>&1 | tee "$out"
status=${PIPESTATUS[0]}
set -e

if [ "$status" -ne 0 ]; then
    echo "::error::gnatprove exited $status"
    exit 1
fi

# Parse the output rather than trusting the exit status: a run can report
# unproved checks without failing, depending on invocation.
if grep -qiE '(medium|high|low):|might fail|not proved|cannot prove' "$out"; then
    echo "::error::gnatprove reported unproved checks — see the output above"
    exit 1
fi

# A justified check is one a human waved through (pragma Annotate), and a
# pragma Assume is an unproved premise the provers then build on. Either
# widens the trusted base the way believe_me does in the Idris ABI, so neither
# counts as proved here.
if grep -qiE ': info: .*justified' "$out"; then
    echo "::error::gnatprove reported justified checks; a justification is not a proof:"
    grep -iE ': info: .*justified' "$out" | sed 's/^/    /'
    exit 1
fi

if [ ! -f "$SUMMARY" ]; then
    echo "::error::$SUMMARY was not written by this run, so its totals cannot be trusted"
    exit 1
fi
# The Total row ends with the Justified and Unproved columns; both must be '.'.
# Anything else, including a row that is missing or has changed shape, fails.
total_row=$(grep -E '^Total[[:space:]]' "$SUMMARY" || true)
total=$(awk '{ print $2 }' <<<"$total_row")
justified_unproved=$(awk '{ print $(NF-1), $NF }' <<<"$total_row")
if ! [[ "$total" =~ ^[1-9][0-9]*$ ]] || [ "$justified_unproved" != ". ." ]; then
    echo "::error::the summary's Total row must show checks and no justified or unproved ones:"
    echo "    ${total_row:-<no Total row in $SUMMARY>}"
    exit 1
fi
if grep -qE '[1-9][0-9]* pragma Assume' "$SUMMARY"; then
    echo "::error::the analysis relies on pragma Assume, an unproved premise:"
    grep -E '[1-9][0-9]* pragma Assume' "$SUMMARY" | sed 's/^/    /'
    exit 1
fi
# Every subprogram of the model must have been analysed, not skipped.
if ! grep -qE '^in unit ums_zones, ([0-9]+) subprograms and packages out of \1 analyzed' "$SUMMARY"; then
    echo "::error::not every subprogram of unit ums_zones was analysed:"
    grep -E '^in unit ums_zones,' "$SUMMARY" | sed 's/^/    /' || echo "    <no line for unit ums_zones>"
    exit 1
fi

# The deliverable is Zones_Ordered's postcondition: the linear sweep decides
# the quadratic specification. "No unproved checks" is not enough on its own,
# because deleting the Post aspect also leaves nothing unproved. Find the line
# the aspect is on and require gnatprove's own statement that it was proved.
post_line=$(awk '/function Zones_Ordered/ { f = 1 } f && /Post[[:space:]]*=>/ { print NR; exit }' spark/src/ums_zones.ads)
if [ -z "$post_line" ]; then
    echo "::error::spark/src/ums_zones.ads has no Post aspect on Zones_Ordered, so there is nothing to prove"
    exit 1
fi
if ! grep -qE "^ums_zones\.ads:${post_line}:[0-9]+: info: postcondition proved" "$out"; then
    echo "::error::gnatprove did not report Zones_Ordered's postcondition (ums_zones.ads:${post_line}) as proved"
    exit 1
fi

echo "proof-check-spark: ${total} checks, none justified or unproved; Zones_Ordered's postcondition (ums_zones.ads:${post_line}) is proved"
