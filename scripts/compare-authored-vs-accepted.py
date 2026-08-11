#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
"""Assert the loader built what the author wrote.

ADR-0014 requires a profile's round trip to compare the loaded model against
the post-edit model. The rest of the gate proves the game *accepted* the
artifact and *replayed* it deterministically -- both weaker claims: a compiler
that silently dropped a taxonomy term or retimed a command would still produce
a package the game accepts and replays identically to itself.

Deliberately does not compare `scenario`. The compiler copies the game-owned
fixture into the package verbatim, so diffing it back would prove only that
serde round-trips JSON.

usage: compare-authored-vs-accepted.py <source.ums.json> <runner-result.json>
"""
import json, sys

FIELDS = ["scenario_id", "seed", "run_ticks", "snapshot_tick",
          "taxonomy", "actors", "commands", "guarantees"]

def main(src_path, result_path):
    authored = json.load(open(src_path))["package"]
    result = json.load(open(result_path))
    accepted = result.get("accepted")
    if accepted is None:
        sys.exit("FAIL: runner result has no 'accepted' field -- the game is "
                 "too old to export what it built; nothing can be compared.")
    bad = []
    for f in FIELDS:
        if authored.get(f) != accepted.get(f):
            bad.append(f)
    if bad:
        for f in bad:
            print(f"  {f}:", file=sys.stderr)
            print(f"    authored: {json.dumps(authored.get(f))[:200]}", file=sys.stderr)
            print(f"    accepted: {json.dumps(accepted.get(f))[:200]}", file=sys.stderr)
        sys.exit(f"FAIL: {len(bad)} authored field(s) did not survive the trip: "
                 + ", ".join(bad))
    print(f"authored-vs-accepted: all {len(FIELDS)} authored fields survived "
          f"({len(accepted['taxonomy'])} taxonomy terms, "
          f"{len(accepted['actors'])} actors, {len(accepted['commands'])} commands)")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
