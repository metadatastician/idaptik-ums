# SPDX-License-Identifier: MPL-2.0
"""CLI driver for the AI-edit engine.

Usage:
    python3 -m ai_edit check <edit-script.json> [<level.json>] [--out <path>]
    python3 -m ai_edit solve <goal.json> [<level.json>] [-n <count>]

`check` applies an idaptik-edit/1 script to a level (an empty level when no
level file is given), prints the report as JSON, and exits 0 only when
every verb was applied with all validity proofs satisfied. `--out` writes
the resulting level state.

`solve` reads a goal spec — a single edit whose finite-domain arguments may
be "?" — and prints up to `n` concrete edits (default 5) whose resulting
states satisfy all proofs.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from .engine import apply_edit_script, solve
from .verbs import initial_state


def _load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _usage():
    print(__doc__.strip(), file=sys.stderr)
    return 2


def _cmd_check(args):
    out_path = None
    if "--out" in args:
        index = args.index("--out")
        try:
            out_path = args[index + 1]
        except IndexError:
            return _usage()
        args = args[:index] + args[index + 2:]
    if not 1 <= len(args) <= 2:
        return _usage()
    script = _load(args[0])
    state = _load(args[1]) if len(args) == 2 else initial_state()
    new_state, report = apply_edit_script(state, script)
    print(json.dumps(report, indent=2))
    if out_path:
        Path(out_path).write_text(
            json.dumps(new_state, indent=2) + "\n", encoding="utf-8"
        )
    return 0 if report["ok"] else 1


def _cmd_solve(args):
    count = 5
    if "-n" in args:
        index = args.index("-n")
        try:
            count = int(args[index + 1])
        except (IndexError, ValueError):
            return _usage()
        args = args[:index] + args[index + 2:]
    if not 1 <= len(args) <= 2:
        return _usage()
    goal_spec = _load(args[0])
    state = _load(args[1]) if len(args) == 2 else initial_state()
    try:
        proposals = solve(state, goal_spec, n=count)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    print(json.dumps([p["edit"] for p in proposals], indent=2))
    return 0 if proposals else 1


def main(argv):
    if len(argv) < 2:
        return _usage()
    command, args = argv[1], argv[2:]
    if command == "check":
        return _cmd_check(args)
    if command == "solve":
        return _cmd_solve(args)
    return _usage()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
