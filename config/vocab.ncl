# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# vocab.ncl — the closed worlds of the IDApTIK level object graph.
#
# THIS IS THE SOURCE OF TRUTH. Every other copy is generated from it.
#
# Before this file, the same vocabularies were hand-maintained in six places:
#
#   ai_edit/vocab.py              the relational engine's domains
#   schemas/edit-script.schema.json   inline `enum` arrays
#   scripts/validate_dlc.py       validator constants
#   schemas/taxonomy-map.json     device-kinds / zone-segments
#   abi/Types.idr                 Idris2 ABI enums
#   ffi/zig/src/types.zig         Zig FFI enums
#
# vocab.py's own docstring conceded the problem: "Keep them in lockstep with
# schemas/edit-script.schema.json and the constants in scripts/validate_dlc.py."
# Nothing enforced that. `just gen-check` now does.
#
# Closed worlds are what make generation decidable (docs/adr/0001): the
# relational engine enumerates over these when an edit leaves a field fresh.

# A vocabulary is a non-empty array of distinct PascalCase identifiers.
# Enforced here rather than downstream so a malformed vocabulary cannot reach
# any of the generated targets. config/bad/bad_*.ncl exercise each clause.
let Checked =
  std.contract.from_validator (fun value =>
    if !std.is_array value then
      'Error { message = "vocabulary must be an array" }
    else if std.array.length value == 0 then
      'Error { message = "vocabulary must not be empty: an empty domain makes its relation unsatisfiable" }
    else if std.array.any (fun x => !std.is_string x) value then
      'Error { message = "vocabulary members must be strings" }
    else if std.array.any (fun x => !std.string.is_match "^[A-Z][A-Za-z0-9]*$" x) value then
      'Error { message = "vocabulary members must be PascalCase, e.g. \"AccessPoint\"" }
    else if
      std.array.length
        (std.array.fold_left
          (fun acc x => if std.array.elem x acc then acc else acc @ [x])
          []
          value)
      != std.array.length value
    then
      'Error { message = "vocabulary members must be distinct: a closed world is a set" }
    else
      'Ok)
in

{
  # Inherited from the archive editor's Idris2 ABI (Types.idr).
  device_kinds | Checked = [
    "Laptop", "Desktop", "Server", "Router", "Switch", "Firewall",
    "Camera", "AccessPoint", "PatchPanel", "PowerSupply", "PhoneSystem",
    "FibreHub",
  ],

  guard_ranks | Checked = [
    "BasicGuard", "Enforcer", "AntiHacker", "Sentinel", "Assassin",
    "EliteGuard", "SecurityChief", "RivalHacker",
  ],

  dog_breeds | Checked = ["Patrol", "Bloodhound", "RoboDog"],

  drone_archetypes | Checked = ["Helper", "Hunter", "Killer"],

  wiring_types | Checked = [
    "PatchPanel", "SwitchBackplane", "ServerRack", "FibreSplicing",
    "PBXComms",
  ],

  # UMS-owned additions. Roles for in-level, non-combatant NPCs — the house
  # and street characters the player passes on the way to the Ghost Lobby /
  # Exchange House. Ambient civilians, distinct from the security actors.
  npc_roles | Checked = [
    "Pedestrian", "Shopkeeper", "Resident", "Doorman", "StreetVendor",
    "Busker", "Commuter", "Concierge",
  ],

  # Named-character archetypes (the game's ActorArchetype), the story-role
  # half of the actor-as-data model mirrored from idaptik-core.
  character_archetypes | Checked = [
    "Protagonist", "Handler", "Fixer", "Contact", "Insider", "Rival",
    "Mark", "Bystander",
  ],

  # Character trait modifiers (the game's Modifier), the second half of the
  # ActorArchetype + Modifier pair. Orthogonal to the archetype.
  character_modifiers | Checked = [
    "Unarmed", "Armed", "Disguised", "Alerted", "Wounded", "Corrupt",
    "Loyal", "Undercover",
  ],

  # Categories of placeable objects/items on a level.
  item_categories | Checked = [
    "Keycard", "Document", "Weapon", "Tool", "Loot", "Consumable",
    "Container", "Contraband",
  ],

  # Game network segments a zone grounds to (schemas/taxonomy-map.json).
  zone_segments | Checked = [
    "Lan", "Dmz", "Internal", "Iot", "Management", "Scada", "Isp",
    "Service",
  ],
}
