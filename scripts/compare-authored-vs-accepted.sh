#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Assert the loader built what the author wrote.
#
# ADR-0014 requires a profile's round trip to compare the loaded model against
# the post-edit model. The rest of the gate proves the game *accepted* the
# artifact and *replayed* it deterministically -- both weaker claims: a compiler
# that silently dropped a taxonomy term or retimed a command would still produce
# a package the game accepts and replays identically to itself.
#
# Deliberately does not compare `scenario`. The compiler copies the game-owned
# fixture into the package verbatim, so diffing it back would prove only that
# serde round-trips JSON.

set -euo pipefail

FIELDS=("scenario_id" "seed" "run_ticks" "snapshot_tick" "taxonomy" "actors" "commands" "guarantees")

if [ $# -ne 2 ]; then
    echo
    echo "usage: compare-authored-vs-accepted <source.ums.json> <runner-result.json>"
    exit 1
fi

SRC_PATH="$1"
RESULT_PATH="$2"

# Check source has package field
if ! jq -e '.package' "$SRC_PATH" >/dev/null 2>&1; then
    echo "FAIL: source file has no 'package' field"
    exit 1
fi

# Check result has accepted field
if ! jq -e '.accepted' "$RESULT_PATH" >/dev/null 2>&1; then
    echo "FAIL: runner result has no 'accepted' field -- the game is too old to export what it built; nothing can be compared."
    exit 1
fi

# Compare each field
BAD=()
for field in "${FIELDS[@]}"; do
    AUTHORED_VAL=$(jq -c ".package.\"$field\"" "$SRC_PATH" 2>/dev/null || echo "null")
    ACCEPTED_VAL=$(jq -c ".accepted.\"$field\"" "$RESULT_PATH" 2>/dev/null || echo "null")
    
    if [ "$AUTHORED_VAL" != "$ACCEPTED_VAL" ]; then
        BAD+=("$field")
    fi
done

if [ ${#BAD[@]} -gt 0 ]; then
    echo "FAIL: ${#BAD[@]} authored field(s) did not survive the trip:"
    for field in "${BAD[@]}"; do
        echo "  $field:"
        AUTHORED_VAL=$(jq ".package.\"$field\"" "$SRC_PATH" 2>/dev/null || echo "null")
        ACCEPTED_VAL=$(jq ".accepted.\"$field\"" "$RESULT_PATH" 2>/dev/null || echo "null")
        echo "    authored: $AUTHORED_VAL"
        echo "    accepted: $ACCEPTED_VAL"
    done
    exit 1
fi

TAXONOMY_LEN=$(jq '.accepted.taxonomy | length' "$RESULT_PATH" 2>/dev/null || echo "0")
ACTORS_LEN=$(jq '.accepted.actors | length' "$RESULT_PATH" 2>/dev/null || echo "0")
COMMANDS_LEN=$(jq '.accepted.commands | length' "$RESULT_PATH" 2>/dev/null || echo "0")

echo "authored-vs-accepted: all ${#FIELDS[@]} authored fields survived (${TAXONOMY_LEN} taxonomy terms, ${ACTORS_LEN} actors, ${COMMANDS_LEN} commands)"
