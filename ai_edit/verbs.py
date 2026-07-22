# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
"""The edit verbs as state-in/state-out relations.

Each verb is a goal constructor ``verb(s_in, args..., s_out)`` relating an
immutable level-state dict to its successor. States are never mutated: the
output state is a fresh dict sharing unchanged values, so edit history is
replayable and each intermediate state remains addressable.

The verb surface matches the archive editor's C ABI (add_zone, add_device,
add_guard, add_dog, add_drone, set_mission, set_physical); create_level is
`initial_state`, and (de)serialisation is plain JSON handled by the script
loader.

Argument terms may be logic variables provided a finite-domain goal grounds
them first (vocabulary relations here; zone domains supplied by
`ai_edit.engine.solve`). A verb whose record is still non-ground when the
state must be built fails rather than embedding variables in a state.
"""

from __future__ import annotations

from . import vocab
from .microkanren import conj, eq, fail, is_ground, project

#: Keys of the level object graph (the archive editor's LevelData, plus the
#: UMS-owned `npcs` and `characters` collections for direct actor edits).
LEVEL_KEYS = (
    "zones", "devices", "guards", "dogs", "drones", "assassins", "items",
    "npcs", "characters", "wiring", "zoneTransitions", "deviceDefences",
    "mission", "physical", "hasPBX", "pbxIp", "pbxWorldX",
)


def initial_state():
    """An empty level (the archive's create_level)."""
    return {
        "zones": [], "devices": [], "guards": [], "dogs": [], "drones": [],
        "assassins": [], "items": [], "npcs": [], "characters": [],
        "wiring": [], "zoneTransitions": [], "deviceDefences": [],
        "mission": None, "physical": None,
        "hasPBX": False, "pbxIp": None, "pbxWorldX": None,
    }


def _append(s_in, s_out, key, record):
    """Goal: s_out is s_in with `record` appended to s_in[key].

    Fails (rather than erring) when the input state or the record is not
    yet ground — ground them first with a domain relation.
    """
    def build(state, rec):
        if not is_ground(state) or not is_ground(rec):
            return fail
        return eq(s_out, {**state, key: state[key] + [rec]})
    return project((s_in, record), build)


def add_zone(s_in, zone_id, security_tier, world_x_start, world_x_end, s_out):
    """Declare a zone: a worldX interval with a security tier."""
    record = {
        "id": zone_id,
        "securityTier": security_tier,
        "worldXStart": world_x_start,
        "worldXEnd": world_x_end,
    }
    return _append(s_in, s_out, "zones", record)


def add_device(s_in, device_id, kind, zone, world_x, s_out):
    """Place a device of a DeviceKind in a zone at a worldX position."""
    record = {"id": device_id, "kind": kind, "zone": zone, "worldX": world_x}
    return conj(
        vocab.device_kindo(kind),
        _append(s_in, s_out, "devices", record),
    )


def add_guard(s_in, guard_id, rank, zone, s_out):
    """Post a guard of a GuardRank in a zone."""
    record = {"id": guard_id, "rank": rank, "zone": zone}
    return conj(
        vocab.guard_ranko(rank),
        _append(s_in, s_out, "guards", record),
    )


def add_dog(s_in, dog_id, breed, zone, s_out):
    """Post a dog of a DogBreed in a zone."""
    record = {"id": dog_id, "breed": breed, "zone": zone}
    return conj(
        vocab.dog_breedo(breed),
        _append(s_in, s_out, "dogs", record),
    )


def add_drone(s_in, drone_id, archetype, zone, s_out):
    """Deploy a drone of a DroneArchetype in a zone."""
    record = {"id": drone_id, "archetype": archetype, "zone": zone}
    return conj(
        vocab.drone_archetypeo(archetype),
        _append(s_in, s_out, "drones", record),
    )


def add_npc(s_in, npc_id, role, zone, s_out):
    """Place an in-level NPC (house/street civilian) of an NPCRole in a zone.

    These are the ambient characters the player passes on the way to the
    Ghost Lobby / Exchange House — first-class edit targets, not scenery.
    """
    record = {"id": npc_id, "role": role, "zone": zone}
    return conj(
        vocab.npc_roleo(role),
        _append(s_in, s_out, "npcs", record),
    )


def add_character(s_in, character_id, archetype, modifier, zone, s_out):
    """Place a named character (the game's ActorArchetype + Modifier) in a zone.

    Characters are actors-as-data: an archetype (story role) paired with a
    trait modifier, both drawn from closed vocabularies so generation stays
    decidable.
    """
    record = {
        "id": character_id,
        "archetype": archetype,
        "modifier": modifier,
        "zone": zone,
    }
    return conj(
        vocab.character_archetypeo(archetype),
        vocab.character_modifiero(modifier),
        _append(s_in, s_out, "characters", record),
    )


def add_item(s_in, item_id, category, zone, s_out):
    """Place an object/item of an ItemCategory in a zone."""
    record = {"id": item_id, "category": category, "zone": zone}
    return conj(
        vocab.item_categoryo(category),
        _append(s_in, s_out, "items", record),
    )


def set_mission(s_in, mission, s_out):
    """Replace the level's mission block (opaque to the engine)."""
    def build(state, block):
        if not is_ground(state) or not is_ground(block):
            return fail
        return eq(s_out, {**state, "mission": block})
    return project((s_in, mission), build)


def set_physical(s_in, physical, s_out):
    """Replace the level's physical block.

    The PBX fields (hasPBX, pbxIp, pbxWorldX) live at the top level of the
    object graph (as in the archive LevelData); when present in the block
    they are lifted there so the PBX consistency proof can see them.
    """
    def build(state, block):
        if not is_ground(state) or not is_ground(block) or not isinstance(block, dict):
            return fail
        new_state = {**state, "physical": block}
        for key in ("hasPBX", "pbxIp", "pbxWorldX"):
            if key in block:
                new_state[key] = block[key]
        return eq(s_out, new_state)
    return project((s_in, physical), build)
