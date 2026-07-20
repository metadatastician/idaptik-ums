# SPDX-License-Identifier: MPL-2.0
"""The AI-edit engine: apply edit scripts, or solve for edits.

Two directions over the same relational kernel:

* `apply_edit_script(state, script)` — the checking direction. Applies the
  script's verbs in order; after every verb the validity proofs
  (ai_edit.constraints) must have a satisfying model or the script is
  rejected at that verb.

* `solve(state, goal_spec, n)` — the generative direction. A goal spec is
  an edit whose finite-domain arguments may be left fresh (the string
  "?"); the engine enumerates up to `n` concrete edits whose resulting
  states satisfy all constraints (generate-and-narrow, not post-hoc
  filtering). This is the seam where a neural proposer plugs in: the
  proposer emits partial edits, the kernel completes or refutes them.
"""

from __future__ import annotations

from collections import namedtuple

from . import constraints, verbs, vocab
from .microkanren import Var, conj, eq, membero, run

#: Placeholder marking an argument the engine should solve for.
FRESH = "?"

#: Guarantees (in the dlc-manifest sense) this engine backs.
GUARANTEES = ("constraint-checked-edits", "replayable-edit-history")

VerbSpec = namedtuple("VerbSpec", ("fn", "args", "domains"))


def _zone_domain(state):
    return [zone["id"] for zone in state["zones"]]


#: Verb registry: relation, argument names (JSON key order), and the finite
#: domains solve() may enumerate when an argument is left fresh.
VERB_SPECS = {
    "add_zone": VerbSpec(
        verbs.add_zone,
        ("id", "securityTier", "worldXStart", "worldXEnd"),
        {},
    ),
    "add_device": VerbSpec(
        verbs.add_device,
        ("id", "kind", "zone", "worldX"),
        {"kind": lambda state: vocab.DEVICE_KINDS, "zone": _zone_domain},
    ),
    "add_guard": VerbSpec(
        verbs.add_guard,
        ("id", "rank", "zone"),
        {"rank": lambda state: vocab.GUARD_RANKS, "zone": _zone_domain},
    ),
    "add_dog": VerbSpec(
        verbs.add_dog,
        ("id", "breed", "zone"),
        {"breed": lambda state: vocab.DOG_BREEDS, "zone": _zone_domain},
    ),
    "add_drone": VerbSpec(
        verbs.add_drone,
        ("id", "archetype", "zone"),
        {"archetype": lambda state: vocab.DRONE_ARCHETYPES, "zone": _zone_domain},
    ),
    "add_npc": VerbSpec(
        verbs.add_npc,
        ("id", "role", "zone"),
        {"role": lambda state: vocab.NPC_ROLES, "zone": _zone_domain},
    ),
    "add_character": VerbSpec(
        verbs.add_character,
        ("id", "archetype", "modifier", "zone"),
        {
            "archetype": lambda state: vocab.CHARACTER_ARCHETYPES,
            "modifier": lambda state: vocab.CHARACTER_MODIFIERS,
            "zone": _zone_domain,
        },
    ),
    "add_item": VerbSpec(
        verbs.add_item,
        ("id", "category", "zone"),
        {"category": lambda state: vocab.ITEM_CATEGORIES, "zone": _zone_domain},
    ),
    "set_mission": VerbSpec(verbs.set_mission, ("mission",), {}),
    "set_physical": VerbSpec(verbs.set_physical, ("physical",), {}),
}


def _satisfiable(state):
    """True when the validity proofs have a model for `state`."""
    return bool(run(1, lambda q: conj(constraints.all_constraints(state),
                                      eq(q, True))))


def apply_edit_script(state, script):
    """Apply `script` to `state`; return ``(new_state, report)``.

    `script` is an idaptik-edit/1 payload dict (or a bare list of edits).
    The input state is checked first; then each verb must leave a state for
    which all constraint goals have a satisfying model, or the script
    is rejected at that verb and the last good state is returned.
    """
    edits = script.get("edits", []) if isinstance(script, dict) else list(script)
    report = {
        "ok": False,
        "applied": 0,
        "total": len(edits),
        "steps": [],
        "guarantees": list(GUARANTEES),
    }

    if not _satisfiable(state):
        report["reason"] = "initial state violates the validity proofs"
        return state, report

    current = state
    for index, edit in enumerate(edits):
        step = {"index": index, "verb": edit.get("verb"), "ok": False}
        report["steps"].append(step)

        spec = VERB_SPECS.get(edit.get("verb"))
        if spec is None:
            step["reason"] = f"unknown verb {edit.get('verb')!r}"
            return current, report
        missing = [name for name in spec.args if name not in edit]
        if missing:
            step["reason"] = f"missing arguments {missing}"
            return current, report
        arg_values = [edit[name] for name in spec.args]
        if FRESH in arg_values:
            step["reason"] = "apply requires ground arguments; use solve()"
            return current, report

        s_out = Var("state")
        goal = conj(
            spec.fn(current, *arg_values, s_out),
            constraints.all_constraints(s_out),
        )
        models = run(1, lambda q: conj(goal, eq(q, s_out)))
        if not models:
            step["reason"] = (
                "no satisfying model: the edit violates the validity proofs "
                "(guards-in-zones, defence-targets, zones-ordered, "
                "pbx-consistent, devices-exist, items-in-zones) or its "
                "vocabulary"
            )
            return current, report

        current = models[0]
        step["ok"] = True
        report["applied"] = index + 1

    report["ok"] = True
    return current, report


def solve(state, goal_spec, n=5):
    """Enumerate up to `n` concrete edits satisfying a partial `goal_spec`.

    `goal_spec` is an edit dict where finite-domain arguments may carry the
    placeholder "?" (FRESH). Returns a list of proposals, each
    ``{"edit": <concrete edit>, "state": <resulting state>}``, in search
    order. Raises ValueError for unknown verbs, missing arguments, or fresh
    arguments with no finite domain to enumerate (ids and geometry must be
    supplied by the caller — today, the neural proposer's job).
    """
    verb = goal_spec.get("verb")
    spec = VERB_SPECS.get(verb)
    if spec is None:
        raise ValueError(f"unknown verb {verb!r}")

    domain_goals = []
    arg_terms = []
    for name in spec.args:
        if name not in goal_spec:
            raise ValueError(f"{verb} requires argument {name!r} (use '?' to solve for it)")
        value = goal_spec[name]
        if value == FRESH:
            domain_fn = spec.domains.get(name)
            if domain_fn is None:
                raise ValueError(
                    f"cannot solve for {verb}.{name}: no finite domain to enumerate"
                )
            variable = Var(name)
            domain_goals.append(membero(variable, list(domain_fn(state))))
            arg_terms.append(variable)
        else:
            arg_terms.append(value)

    s_out = Var("state")
    goal = conj(
        *domain_goals,
        spec.fn(state, *arg_terms, s_out),
        constraints.all_constraints(s_out),
    )
    answers = run(n, lambda q: conj(goal, eq(q, (tuple(arg_terms), s_out))))

    proposals = []
    for args, new_state in answers:
        edit = {"verb": verb, **dict(zip(spec.args, args))}
        proposals.append({"edit": edit, "state": new_state})
    return proposals
