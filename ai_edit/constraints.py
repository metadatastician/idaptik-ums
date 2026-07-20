# SPDX-License-Identifier: MPL-2.0
"""The cross-domain validity proofs as relational goals.

These re-express the archive editor's Idris2 proofs (GuardsInZones,
DefenceTargets, ZonesOrdered, PBXConsistent, DevicesExist) — plus
ItemsInZones for the UMS object collection — as goals over a level-state
term. An AI-proposed edit is only emitted if a model satisfying *all* of
them exists for the resulting state — constraint checking is part of the
same search that generates the edit, not a post-hoc filter.

Each constraint takes a state term (possibly a logic variable bound during
the search) and fails on non-ground states, so goal ordering stays safe.
"""

from __future__ import annotations

from . import vocab
from .microkanren import conj, fail, is_ground, membero, project, succeed


def _over_state(state, fn):
    """Lift `fn(ground_state) -> goal` over a state term."""
    def build(resolved):
        if not is_ground(resolved) or not isinstance(resolved, dict):
            return fail
        return fn(resolved)
    return project((state,), build)


def _zone_ids(state):
    return [zone["id"] for zone in state["zones"]]


def _device_ids(state):
    return [device["id"] for device in state["devices"]]


def guards_in_zones(state):
    """GuardsInZones: every mobile actor — security actors (guard, dog,
    drone, assassin) and inhabitants (NPCs, named characters) — stands in a
    declared zone."""
    def goal(st):
        zone_ids = _zone_ids(st)
        actors = (
            st["guards"] + st["dogs"] + st["drones"] + st["assassins"]
            + st.get("npcs", []) + st.get("characters", [])
        )
        return conj(*(membero(actor["zone"], zone_ids) for actor in actors))
    return _over_state(state, goal)


def defence_targets_exist(state):
    """DefenceTargets: every device defence targets an existing device."""
    def goal(st):
        device_ids = _device_ids(st)
        return conj(
            *(membero(defence["target"], device_ids)
              for defence in st["deviceDefences"])
        )
    return _over_state(state, goal)


def zones_ordered(state):
    """ZonesOrdered: zone worldX intervals are well-formed and disjoint,
    and security tiers do not decrease as worldX increases (deeper into
    the building means at least as hardened)."""
    def goal(st):
        ordered = sorted(st["zones"], key=lambda z: z["worldXStart"])
        previous_end = None
        previous_tier = None
        for zone in ordered:
            if zone["worldXStart"] > zone["worldXEnd"]:
                return fail
            if previous_end is not None and zone["worldXStart"] < previous_end:
                return fail
            if previous_tier is not None and zone["securityTier"] < previous_tier:
                return fail
            previous_end = zone["worldXEnd"]
            previous_tier = zone["securityTier"]
        return succeed
    return _over_state(state, goal)


def pbx_consistent(state):
    """PBXConsistent: hasPBX implies a PBX IP, a PBX worldX position and a
    PhoneSystem device; no PBX implies no dangling PBX fields."""
    def goal(st):
        if st.get("hasPBX"):
            ip = st.get("pbxIp")
            has_ip = isinstance(ip, str) and bool(ip)
            has_position = st.get("pbxWorldX") is not None
            has_phone_system = any(
                device["kind"] == "PhoneSystem" for device in st["devices"]
            )
            return succeed if has_ip and has_position and has_phone_system else fail
        dangling = st.get("pbxIp") is not None or st.get("pbxWorldX") is not None
        return fail if dangling else succeed
    return _over_state(state, goal)


def devices_exist(state):
    """DevicesExist: every device sits in a declared zone, and every wiring
    run has a known WiringType and connects existing devices."""
    def goal(st):
        zone_ids = _zone_ids(st)
        device_ids = _device_ids(st)
        goals = [membero(device["zone"], zone_ids) for device in st["devices"]]
        for run in st["wiring"]:
            if not isinstance(run, dict):
                return fail
            goals.append(vocab.wiring_typeo(run.get("type")))
            goals.append(membero(run.get("from"), device_ids))
            goals.append(membero(run.get("to"), device_ids))
        return conj(*goals)
    return _over_state(state, goal)


def items_in_zones(state):
    """ItemsInZones: every placed object/item sits in a declared zone (no
    orphaned loot floating outside the level geometry)."""
    def goal(st):
        zone_ids = _zone_ids(st)
        return conj(
            *(membero(item["zone"], zone_ids) for item in st.get("items", []))
        )
    return _over_state(state, goal)


#: The six proofs, in the order the report lists them.
ALL_CONSTRAINTS = (
    guards_in_zones,
    defence_targets_exist,
    zones_ordered,
    pbx_consistent,
    devices_exist,
    items_in_zones,
)


def all_constraints(state):
    """Goal: the state satisfies all six validity proofs."""
    return conj(*(constraint(state) for constraint in ALL_CONSTRAINTS))
