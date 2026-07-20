# SPDX-License-Identifier: MPL-2.0
"""Finite vocabularies of the IDApTIK level object graph, as data plus
membero-style domain relations.

These mirror the archive editor's Idris2 ABI enums (Types.idr): the closed
worlds the relational engine enumerates over when an edit leaves a field
fresh. Keep them in lockstep with schemas/edit-script.schema.json and the
constants in scripts/validate_dlc.py.
"""

from __future__ import annotations

from .microkanren import membero

DEVICE_KINDS = (
    "Laptop", "Desktop", "Server", "Router", "Switch", "Firewall",
    "Camera", "AccessPoint", "PatchPanel", "PowerSupply", "PhoneSystem",
    "FibreHub",
)

GUARD_RANKS = (
    "BasicGuard", "Enforcer", "AntiHacker", "Sentinel", "Assassin",
    "EliteGuard", "SecurityChief", "RivalHacker",
)

DOG_BREEDS = ("Patrol", "Bloodhound", "RoboDog")

DRONE_ARCHETYPES = ("Helper", "Hunter", "Killer")

WIRING_TYPES = (
    "PatchPanel", "SwitchBackplane", "ServerRack", "FibreSplicing",
    "PBXComms",
)

#: Roles for in-level, non-combatant NPCs — the house and street characters
#: the player passes on the way to the Ghost Lobby / Exchange House. These
#: are the ambient civilian actors, distinct from the guard/dog/drone
#: security actors above.
NPC_ROLES = (
    "Pedestrian", "Shopkeeper", "Resident", "Doorman", "StreetVendor",
    "Busker", "Commuter", "Concierge",
)

#: Named-character archetypes (the game's ActorArchetype), the story-role
#: half of the actor-as-data model mirrored from idaptik-core.
CHARACTER_ARCHETYPES = (
    "Protagonist", "Handler", "Fixer", "Contact", "Insider", "Rival",
    "Mark", "Bystander",
)

#: Character trait modifiers (the game's Modifier), the second half of the
#: ActorArchetype + Modifier pair. Orthogonal to the archetype.
CHARACTER_MODIFIERS = (
    "Unarmed", "Armed", "Disguised", "Alerted", "Wounded", "Corrupt",
    "Loyal", "Undercover",
)

#: Categories of placeable objects/items on a level.
ITEM_CATEGORIES = (
    "Keycard", "Document", "Weapon", "Tool", "Loot", "Consumable",
    "Container", "Contraband",
)


def device_kindo(kind):
    """Goal: `kind` is a DeviceKind (enumerates all twelve when fresh)."""
    return membero(kind, DEVICE_KINDS)


def guard_ranko(rank):
    """Goal: `rank` is a GuardRank."""
    return membero(rank, GUARD_RANKS)


def dog_breedo(breed):
    """Goal: `breed` is a DogBreed."""
    return membero(breed, DOG_BREEDS)


def drone_archetypeo(archetype):
    """Goal: `archetype` is a DroneArchetype."""
    return membero(archetype, DRONE_ARCHETYPES)


def wiring_typeo(wiring_type):
    """Goal: `wiring_type` is a WiringType."""
    return membero(wiring_type, WIRING_TYPES)


def npc_roleo(role):
    """Goal: `role` is an NPCRole (an in-level civilian role)."""
    return membero(role, NPC_ROLES)


def character_archetypeo(archetype):
    """Goal: `archetype` is a CharacterArchetype (the game's ActorArchetype)."""
    return membero(archetype, CHARACTER_ARCHETYPES)


def character_modifiero(modifier):
    """Goal: `modifier` is a CharacterModifier (the game's Modifier)."""
    return membero(modifier, CHARACTER_MODIFIERS)


def item_categoryo(category):
    """Goal: `category` is an ItemCategory."""
    return membero(category, ITEM_CATEGORIES)
