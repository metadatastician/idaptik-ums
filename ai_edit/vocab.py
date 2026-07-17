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
