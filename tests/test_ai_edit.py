# SPDX-License-Identifier: MPL-2.0
"""Tests for the ai_edit relational engine.

Run from the repository root with:
    python3 -m unittest discover -s tests
"""

from __future__ import annotations

import unittest

from ai_edit import apply_edit_script, initial_state, solve
from ai_edit import constraints, verbs, vocab
from ai_edit.microkanren import (
    Var, conde, conj, delay, disj, eq, fresh, membero, run, unify, walk,
)


def _run_verb(goal_fn):
    """Run a verb goal for one output state; [] means no model."""
    return run(1, lambda q: goal_fn(q))


def _base_state():
    """Two ordered zones, a server, and a phone system: all proofs hold."""
    state = initial_state()
    state["zones"] = [
        {"id": "lobby", "securityTier": 0, "worldXStart": 0, "worldXEnd": 40},
        {"id": "server-room", "securityTier": 2, "worldXStart": 40, "worldXEnd": 80},
    ]
    state["devices"] = [
        {"id": "rack-1", "kind": "Server", "zone": "server-room", "worldX": 50},
        {"id": "pbx-1", "kind": "PhoneSystem", "zone": "lobby", "worldX": 10},
    ]
    return state


class MicroKanrenTests(unittest.TestCase):
    def test_unify_atoms_and_vars(self):
        x, y = Var("x"), Var("y")
        subst = unify(x, 1, {})
        self.assertEqual(walk(x, subst), 1)
        subst = unify((x, 2), (1, y), {})
        self.assertEqual(walk(x, subst), 1)
        self.assertEqual(walk(y, subst), 2)
        self.assertIsNone(unify(1, 2, {}))
        self.assertIsNone(unify({"a": 1}, {"b": 1}, {}))

    def test_eq_and_run(self):
        self.assertEqual(run(None, lambda q: eq(q, 42)), [42])
        self.assertEqual(run(None, lambda q: conj(eq(q, 1), eq(q, 2))), [])

    def test_conde_enumerates_alternatives(self):
        answers = run(None, lambda q: conde([eq(q, "a")], [eq(q, "b")], [eq(q, "c")]))
        self.assertEqual(sorted(answers), ["a", "b", "c"])

    def test_fresh_introduces_scoped_variables(self):
        goal = lambda q: fresh(lambda x, y: conj(eq(x, 5), eq(y, x), eq(q, (x, y))))
        self.assertEqual(run(None, goal), [(5, 5)])

    def test_recursive_goal_with_delay_and_interleaving(self):
        def nats(x, start=0):
            return disj(eq(x, start), delay(lambda: nats(x, start + 1)))
        self.assertEqual(run(5, lambda q: nats(q)), [0, 1, 2, 3, 4])
        # Interleaving: both infinite branches contribute answers.
        both = run(6, lambda q: disj(nats(q, 0), nats(q, 100)))
        self.assertTrue(any(n >= 100 for n in both))
        self.assertTrue(any(n < 100 for n in both))

    def test_membero_checks_and_generates(self):
        check = lambda q: conj(membero("b", ("a", "b")), eq(q, True))
        self.assertEqual(run(None, check), [True])
        self.assertEqual(run(None, lambda q: membero(q, ("a", "b"))), ["a", "b"])


class VerbTests(unittest.TestCase):
    def test_add_zone(self):
        goal = lambda q: verbs.add_zone(initial_state(), "lobby", 0, 0, 40, q)
        (state,) = _run_verb(goal)
        self.assertEqual(state["zones"], [
            {"id": "lobby", "securityTier": 0, "worldXStart": 0, "worldXEnd": 40},
        ])

    def test_add_device_and_kind_vocabulary(self):
        base = _base_state()
        goal = lambda q: verbs.add_device(base, "cam-1", "Camera", "lobby", 5, q)
        (state,) = _run_verb(goal)
        self.assertEqual(state["devices"][-1]["kind"], "Camera")
        bogus = lambda q: verbs.add_device(base, "cam-2", "Toaster", "lobby", 5, q)
        self.assertEqual(_run_verb(bogus), [])

    def test_add_guard(self):
        goal = lambda q: verbs.add_guard(_base_state(), "g-1", "Sentinel", "lobby", q)
        (state,) = _run_verb(goal)
        self.assertEqual(state["guards"], [{"id": "g-1", "rank": "Sentinel", "zone": "lobby"}])
        bogus = lambda q: verbs.add_guard(_base_state(), "g-2", "Janitor", "lobby", q)
        self.assertEqual(_run_verb(bogus), [])

    def test_add_dog(self):
        goal = lambda q: verbs.add_dog(_base_state(), "d-1", "Bloodhound", "lobby", q)
        (state,) = _run_verb(goal)
        self.assertEqual(state["dogs"][0]["breed"], "Bloodhound")

    def test_add_drone(self):
        goal = lambda q: verbs.add_drone(_base_state(), "dr-1", "Hunter", "lobby", q)
        (state,) = _run_verb(goal)
        self.assertEqual(state["drones"][0]["archetype"], "Hunter")

    def test_set_mission(self):
        mission = {"objective": "exfiltrate", "targetDevice": "rack-1"}
        goal = lambda q: verbs.set_mission(_base_state(), mission, q)
        (state,) = _run_verb(goal)
        self.assertEqual(state["mission"], mission)

    def test_set_physical_lifts_pbx_fields(self):
        block = {"hasPBX": True, "pbxIp": "10.0.0.1", "pbxWorldX": 10}
        goal = lambda q: verbs.set_physical(_base_state(), block, q)
        (state,) = _run_verb(goal)
        self.assertTrue(state["hasPBX"])
        self.assertEqual(state["pbxIp"], "10.0.0.1")
        self.assertEqual(state["pbxWorldX"], 10)
        self.assertEqual(state["physical"], block)

    def test_verbs_do_not_mutate_input_state(self):
        base = _base_state()
        before = repr(base)
        _run_verb(lambda q: verbs.add_guard(base, "g-1", "Sentinel", "lobby", q))
        self.assertEqual(repr(base), before)


class ConstraintTests(unittest.TestCase):
    def _holds(self, constraint, state):
        return bool(run(1, lambda q: conj(constraint(state), eq(q, True))))

    def test_guards_in_zones(self):
        good = _base_state()
        good["guards"] = [{"id": "g", "rank": "Sentinel", "zone": "lobby"}]
        self.assertTrue(self._holds(constraints.guards_in_zones, good))
        bad = _base_state()
        bad["guards"] = [{"id": "g", "rank": "Sentinel", "zone": "roof"}]
        self.assertFalse(self._holds(constraints.guards_in_zones, bad))

    def test_defence_targets_exist(self):
        good = _base_state()
        good["deviceDefences"] = [{"defence": "firewall-rule", "target": "rack-1"}]
        self.assertTrue(self._holds(constraints.defence_targets_exist, good))
        bad = _base_state()
        bad["deviceDefences"] = [{"defence": "firewall-rule", "target": "ghost"}]
        self.assertFalse(self._holds(constraints.defence_targets_exist, bad))

    def test_zones_ordered(self):
        self.assertTrue(self._holds(constraints.zones_ordered, _base_state()))
        overlapping = _base_state()
        overlapping["zones"][1]["worldXStart"] = 30
        self.assertFalse(self._holds(constraints.zones_ordered, overlapping))
        tier_inverted = _base_state()
        tier_inverted["zones"][0]["securityTier"] = 5
        self.assertFalse(self._holds(constraints.zones_ordered, tier_inverted))

    def test_pbx_consistent(self):
        good = _base_state()
        good.update(hasPBX=True, pbxIp="10.0.0.1", pbxWorldX=10)
        self.assertTrue(self._holds(constraints.pbx_consistent, good))
        no_phone_system = _base_state()
        no_phone_system["devices"] = [d for d in no_phone_system["devices"]
                                      if d["kind"] != "PhoneSystem"]
        no_phone_system.update(hasPBX=True, pbxIp="10.0.0.1", pbxWorldX=10)
        self.assertFalse(self._holds(constraints.pbx_consistent, no_phone_system))
        missing_ip = _base_state()
        missing_ip.update(hasPBX=True, pbxWorldX=10)
        self.assertFalse(self._holds(constraints.pbx_consistent, missing_ip))
        dangling = _base_state()
        dangling["pbxIp"] = "10.0.0.1"
        self.assertFalse(self._holds(constraints.pbx_consistent, dangling))

    def test_devices_exist(self):
        good = _base_state()
        good["wiring"] = [{"type": "ServerRack", "from": "rack-1", "to": "pbx-1"}]
        self.assertTrue(self._holds(constraints.devices_exist, good))
        orphan_device = _base_state()
        orphan_device["devices"][0]["zone"] = "roof"
        self.assertFalse(self._holds(constraints.devices_exist, orphan_device))
        bad_wire = _base_state()
        bad_wire["wiring"] = [{"type": "ServerRack", "from": "rack-1", "to": "ghost"}]
        self.assertFalse(self._holds(constraints.devices_exist, bad_wire))


class EngineTests(unittest.TestCase):
    def test_apply_edit_script_accepts_a_valid_script(self):
        script = {
            "target": "exchange-house",
            "edits": [
                {"verb": "add_zone", "id": "lobby", "securityTier": 0,
                 "worldXStart": 0, "worldXEnd": 40},
                {"verb": "add_zone", "id": "server-room", "securityTier": 2,
                 "worldXStart": 40, "worldXEnd": 80},
                {"verb": "add_device", "id": "pbx-1", "kind": "PhoneSystem",
                 "zone": "lobby", "worldX": 10},
                {"verb": "add_guard", "id": "g-1", "rank": "Sentinel",
                 "zone": "server-room"},
                {"verb": "set_mission",
                 "mission": {"objective": "exfiltrate", "targetDevice": "pbx-1"}},
                {"verb": "set_physical",
                 "physical": {"hasPBX": True, "pbxIp": "10.0.0.1", "pbxWorldX": 10}},
            ],
        }
        state, report = apply_edit_script(initial_state(), script)
        self.assertTrue(report["ok"], report)
        self.assertEqual(report["applied"], 6)
        self.assertEqual(len(state["zones"]), 2)
        self.assertTrue(state["hasPBX"])
        self.assertIn("constraint-checked-edits", report["guarantees"])

    def test_apply_edit_script_rejects_guard_outside_zones(self):
        script = {
            "target": "exchange-house",
            "edits": [
                {"verb": "add_zone", "id": "lobby", "securityTier": 0,
                 "worldXStart": 0, "worldXEnd": 40},
                {"verb": "add_guard", "id": "g-1", "rank": "Sentinel",
                 "zone": "roof"},
            ],
        }
        state, report = apply_edit_script(initial_state(), script)
        self.assertFalse(report["ok"])
        self.assertEqual(report["applied"], 1)
        self.assertFalse(report["steps"][1]["ok"])
        self.assertIn("no satisfying model", report["steps"][1]["reason"])
        # The last good state is returned: the zone landed, the guard did not.
        self.assertEqual(len(state["zones"]), 1)
        self.assertEqual(state["guards"], [])

    def test_apply_edit_script_rejects_pbx_without_phone_system(self):
        script = {
            "target": "exchange-house",
            "edits": [
                {"verb": "add_zone", "id": "lobby", "securityTier": 0,
                 "worldXStart": 0, "worldXEnd": 40},
                {"verb": "set_physical",
                 "physical": {"hasPBX": True, "pbxIp": "10.0.0.1", "pbxWorldX": 10}},
            ],
        }
        _, report = apply_edit_script(initial_state(), script)
        self.assertFalse(report["ok"])
        self.assertFalse(report["steps"][1]["ok"])

    def test_apply_edit_script_rejects_unknown_verb(self):
        _, report = apply_edit_script(initial_state(),
                                      {"edits": [{"verb": "summon_dragon"}]})
        self.assertFalse(report["ok"])
        self.assertIn("unknown verb", report["steps"][0]["reason"])

    def test_solve_proposes_zones_for_a_guard(self):
        goal_spec = {"verb": "add_guard", "id": "g-9", "rank": "Sentinel",
                     "zone": "?"}
        proposals = solve(_base_state(), goal_spec, n=10)
        zones = {p["edit"]["zone"] for p in proposals}
        self.assertEqual(zones, {"lobby", "server-room"})
        for proposal in proposals:
            self.assertEqual(proposal["edit"]["rank"], "Sentinel")
            self.assertEqual(proposal["state"]["guards"][-1]["id"], "g-9")

    def test_solve_enumerates_ranks(self):
        goal_spec = {"verb": "add_guard", "id": "g-9", "rank": "?",
                     "zone": "lobby"}
        proposals = solve(_base_state(), goal_spec, n=None)
        ranks = {p["edit"]["rank"] for p in proposals}
        self.assertEqual(ranks, set(vocab.GUARD_RANKS))

    def test_solve_refuses_fresh_arguments_without_a_domain(self):
        with self.assertRaises(ValueError):
            solve(_base_state(), {"verb": "add_guard", "id": "?",
                                  "rank": "Sentinel", "zone": "lobby"})


if __name__ == "__main__":
    unittest.main()
