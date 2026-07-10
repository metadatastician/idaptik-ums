#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""UMS <-> game bridge smoke test.

Validates every DLC artifact in dlc/ against the contracts in schemas/:
manifest envelopes (dlc-manifest.schema.json) and puzzle payloads
(puzzle.schema.json), including the cross-field invariants the schema
language cannot express. Stdlib only, so `just dlc-check` works on a bare
Debian/CI box.

Exit code 0 = every artifact valid; 1 = at least one violation (all are
reported, not just the first).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DLC = ROOT / "dlc"

SEMVER = re.compile(r"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$")
KEBAB = re.compile(r"^[a-z0-9][a-z0-9-]*$")
IDENT = re.compile(r"^[a-z][a-z0-9_]*$")
ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
PAYLOAD_FORMAT = re.compile(r"^idaptik-(scenario|actors|puzzles|assets)/\d+$")

MANIFEST_KINDS = {
    "gameplay-mechanic",
    "puzzle-pack",
    "scenario-definition",
    "actor-pack",
    "asset-pack",
}
COMPILE_TARGETS = {"wasmgc", "wasm32", "none"}
MANIFEST_REQUIRED = {"id", "name", "version", "description", "license", "kind"}
MANIFEST_ALLOWED = MANIFEST_REQUIRED | {
    "$schema", "author", "loads", "exports", "depends-on",
    "compile-target", "wasm-modules", "payload", "guarantees", "verification",
}

INSTRUCTIONS = {
    "ADD", "AND", "CALL", "DIV", "FLIP", "IFPOS", "IFZERO", "LOAD",
    "LOOP", "MUL", "NEGATE", "NOOP", "OR", "POP", "PUSH", "RECV",
    "ROL", "ROR", "SEND", "STORE", "SUB", "SWAP", "XOR",
}
DIFFICULTIES = {"beginner", "intermediate", "advanced", "expert"}
PUZZLE_REQUIRED = {
    "name", "description", "difficulty", "initialState", "goalState",
    "maxMoves", "optimalMoves", "allowedInstructions", "hints", "metadata",
}
METADATA_ALLOWED = {"author", "created", "tags", "license", "version"}
VAULT_REQUIRED = {"name", "description", "state", "steps"}
VAULT_OPS = {"flip", "xor", "swap"}


def is_register_state(value, bits_only=False):
    if not isinstance(value, dict) or not value:
        return False
    for key, item in value.items():
        if not IDENT.match(key):
            return False
        if not isinstance(item, int) or isinstance(item, bool):
            return False
        if bits_only and item not in (0, 1):
            return False
    return True


def check_manifest(doc, errors):
    missing = MANIFEST_REQUIRED - doc.keys()
    if missing:
        errors.append(f"manifest missing required fields: {sorted(missing)}")
    unknown = doc.keys() - MANIFEST_ALLOWED
    if unknown:
        errors.append(f"manifest has unknown fields: {sorted(unknown)}")
    if "id" in doc and not (isinstance(doc["id"], str) and KEBAB.match(doc["id"])):
        errors.append("id must be lowercase-kebab")
    if "version" in doc and not (isinstance(doc["version"], str) and SEMVER.match(doc["version"])):
        errors.append("version must be semver")
    for field in ("name", "description", "license"):
        if field in doc and not (isinstance(doc[field], str) and doc[field]):
            errors.append(f"{field} must be a non-empty string")
    if "kind" in doc and doc["kind"] not in MANIFEST_KINDS:
        errors.append(f"kind must be one of {sorted(MANIFEST_KINDS)}")
    if "compile-target" in doc and doc["compile-target"] not in COMPILE_TARGETS:
        errors.append(f"compile-target must be one of {sorted(COMPILE_TARGETS)}")
    for field in ("exports", "depends-on", "verification"):
        value = doc.get(field)
        if value is not None and not (
            isinstance(value, dict)
            and all(isinstance(v, str) for v in value.values())
        ):
            errors.append(f"{field} must map names to strings")
    for field in ("wasm-modules", "guarantees"):
        value = doc.get(field)
        if value is not None and not (
            isinstance(value, list) and all(isinstance(v, str) for v in value)
        ):
            errors.append(f"{field} must be an array of strings")
    payload = doc.get("payload")
    if payload is not None:
        if not isinstance(payload, dict):
            errors.append("payload must be an object")
        else:
            if payload.keys() - {"format", "path"} or {"format", "path"} - payload.keys():
                errors.append("payload must have exactly format and path")
            fmt = payload.get("format")
            if not (isinstance(fmt, str) and PAYLOAD_FORMAT.match(fmt)):
                errors.append("payload.format must match idaptik-<type>/<n>")
            path = payload.get("path")
            if not (isinstance(path, str) and path):
                errors.append("payload.path must be a non-empty string")


def check_register_puzzle(doc, errors):
    missing = PUZZLE_REQUIRED - doc.keys()
    if missing:
        errors.append(f"puzzle missing required fields: {sorted(missing)}")
    unknown = doc.keys() - PUZZLE_REQUIRED
    if unknown:
        errors.append(f"puzzle has unknown fields: {sorted(unknown)}")
    if "difficulty" in doc and doc["difficulty"] not in DIFFICULTIES:
        errors.append(f"difficulty must be one of {sorted(DIFFICULTIES)}")
    for field in ("initialState", "goalState"):
        if field in doc and not is_register_state(doc[field]):
            errors.append(f"{field} must map identifiers to integers")
    initial, goal = doc.get("initialState"), doc.get("goalState")
    if isinstance(initial, dict) and isinstance(goal, dict) and initial.keys() != goal.keys():
        errors.append(
            f"initialState and goalState must share one register set "
            f"({sorted(initial)} vs {sorted(goal)})"
        )
    for field in ("maxMoves", "optimalMoves"):
        value = doc.get(field)
        if field in doc and not (isinstance(value, int) and not isinstance(value, bool) and value >= 1):
            errors.append(f"{field} must be an integer >= 1")
    if (
        isinstance(doc.get("maxMoves"), int)
        and isinstance(doc.get("optimalMoves"), int)
        and doc["optimalMoves"] > doc["maxMoves"]
    ):
        errors.append("optimalMoves must be <= maxMoves")
    instructions = doc.get("allowedInstructions")
    if instructions is not None:
        if not (isinstance(instructions, list) and instructions):
            errors.append("allowedInstructions must be a non-empty array")
        else:
            bogus = [i for i in instructions if i not in INSTRUCTIONS]
            if bogus:
                errors.append(f"unknown instructions: {bogus}")
            if len(set(instructions)) != len(instructions):
                errors.append("allowedInstructions must not repeat")
    hints = doc.get("hints")
    if hints is not None:
        if not isinstance(hints, list):
            errors.append("hints must be an array")
        else:
            for i, hint in enumerate(hints):
                if not (
                    isinstance(hint, dict)
                    and hint.keys() == {"moveNumber", "text"}
                    and isinstance(hint.get("moveNumber"), int)
                    and hint["moveNumber"] >= 0
                    and isinstance(hint.get("text"), str)
                    and hint["text"]
                ):
                    errors.append(f"hints[{i}] must be {{moveNumber >= 0, text}}")
    metadata = doc.get("metadata")
    if metadata is not None:
        if not isinstance(metadata, dict):
            errors.append("metadata must be an object")
        else:
            if {"author", "created", "tags"} - metadata.keys():
                errors.append("metadata requires author, created, tags")
            if metadata.keys() - METADATA_ALLOWED:
                errors.append(f"metadata has unknown fields: {sorted(metadata.keys() - METADATA_ALLOWED)}")
            created = metadata.get("created")
            if created is not None and not (isinstance(created, str) and ISO_DATE.match(created)):
                errors.append("metadata.created must be YYYY-MM-DD")
            tags = metadata.get("tags")
            if tags is not None and not (
                isinstance(tags, list) and all(isinstance(t, str) for t in tags)
            ):
                errors.append("metadata.tags must be an array of strings")


def check_vault_sequence(doc, errors):
    missing = VAULT_REQUIRED - doc.keys()
    if missing:
        errors.append(f"vault missing required fields: {sorted(missing)}")
    unknown = doc.keys() - VAULT_REQUIRED
    if unknown:
        errors.append(f"vault has unknown fields: {sorted(unknown)}")
    state = doc.get("state")
    if state is not None and not is_register_state(state, bits_only=True):
        errors.append("state must map identifiers to bits (0/1)")
    bits = set(state) if isinstance(state, dict) else set()
    steps = doc.get("steps")
    if steps is not None:
        if not (isinstance(steps, list) and steps):
            errors.append("steps must be a non-empty array")
        else:
            for i, step in enumerate(steps):
                if not isinstance(step, dict) or step.get("op") not in VAULT_OPS:
                    errors.append(f"steps[{i}].op must be one of {sorted(VAULT_OPS)}")
                    continue
                op = step["op"]
                named = []
                if op == "flip":
                    if step.keys() != {"op", "target"} or not isinstance(step.get("target"), str):
                        errors.append(f"steps[{i}]: flip takes exactly a target bit")
                    named = [step.get("target")]
                elif op == "swap":
                    if step.keys() != {"op", "targets"}:
                        errors.append(f"steps[{i}]: swap takes exactly two targets")
                    named = step.get("targets") or []
                elif op == "xor":
                    if step.keys() not in ({"op", "targets"}, {"op", "targets", "result"}):
                        errors.append(f"steps[{i}]: xor takes two targets and an optional result")
                    named = list(step.get("targets") or []) + (
                        [step["result"]] if isinstance(step.get("result"), str) else []
                    )
                targets = step.get("targets")
                if targets is not None and not (
                    isinstance(targets, list)
                    and len(targets) == 2
                    and all(isinstance(t, str) for t in targets)
                ):
                    errors.append(f"steps[{i}].targets must be exactly two bit names")
                    named = [n for n in named if isinstance(n, str)]
                for bit in named:
                    if isinstance(bit, str) and bits and bit not in bits:
                        errors.append(f"steps[{i}] references unknown bit '{bit}'")


def classify_and_check(path, doc, errors):
    if path.name == "dlc-manifest.json":
        check_manifest(doc, errors)
    elif "steps" in doc or "state" in doc:
        check_vault_sequence(doc, errors)
    else:
        check_register_puzzle(doc, errors)


def main():
    if not DLC.is_dir():
        print(f"error: {DLC} does not exist", file=sys.stderr)
        return 1
    failures = 0
    checked = 0
    for path in sorted(DLC.rglob("*.json")):
        rel = path.relative_to(ROOT)
        checked += 1
        errors = []
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            print(f"FAIL {rel}: unparseable JSON ({exc})")
            failures += 1
            continue
        if not isinstance(doc, dict):
            errors.append("top level must be an object")
        else:
            classify_and_check(path, doc, errors)
        if errors:
            failures += 1
            print(f"FAIL {rel}")
            for error in errors:
                print(f"     - {error}")
        else:
            print(f"ok   {rel}")
    print(f"\n{checked} artifacts checked, {failures} invalid")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
