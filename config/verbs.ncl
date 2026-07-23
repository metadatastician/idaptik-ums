# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# verbs.ncl — the AI-edit verb registry, as data.
#
# THIS IS THE SOURCE OF TRUTH for the closed verb surface. It generates the
# `$defs` of schemas/edit-script.schema.json, and (from PR 3) the Rust verb
# registry that `ums-ai-edit` dispatches on.
#
# Each verb is a state-in/state-out relation over the level object graph
# (docs/adr/0001). What matters to every consumer is the same three facts:
#
#   args     ordered — JSON key order in the wire format is significant, so
#            this is an array, not a record. The engine binds solve()'s
#            positional arguments in exactly this order.
#   domain   the finite vocabulary an argument ranges over, or null when the
#            caller must supply it (ids and geometry are the proposer's job).
#            An argument with a domain may be left fresh ("?") for the
#            relational engine to enumerate — this is what makes an edit
#            generable rather than merely checkable.
#   type     the JSON type, for schema generation.
#
# Declaring the domain here, once, is what lets `solve()` narrow rather than
# filter: the domain relation is conjoined into the same search as the verb
# relation and the validity proofs, so an out-of-vocabulary value is never
# generated in the first place.

let vocab = import "./vocab.ncl" in


let entity_id = fun n => { name = n, type = 'string } in

{
  # Order is the registry's iteration order and the schema's `oneOf` order.
  verbs = [
    {
      name = "add_zone",
      collection = "zones",
      doc = "Declare a zone: a worldX interval with a security tier.",
      args = [
        entity_id "id",
        { name = "securityTier", type = 'integer },
        { name = "worldXStart", type = 'number },
        { name = "worldXEnd", type = 'number },
        # Optional per-zone override of the game network segment this zone
        # grounds to. When absent, securityTier is mapped through the default
        # tier bands in schemas/taxonomy-map.json (ratified 2026-07-21).
        { name = "segment", type = 'string, domain = "zone_segments", required = false },
      ],
    },
    {
      name = "add_device",
      collection = "devices",
      doc = "Place a device of a known kind in a declared zone.",
      args = [
        entity_id "id",
        { name = "kind", type = 'string, domain = "device_kinds" },
        entity_id "zone",
        { name = "worldX", type = 'number },
      ],
    },
    {
      name = "add_guard",
      collection = "guards",
      doc = "Place a security guard of a known rank in a declared zone.",
      args = [
        entity_id "id",
        { name = "rank", type = 'string, domain = "guard_ranks" },
        entity_id "zone",
      ],
    },
    {
      name = "add_dog",
      collection = "dogs",
      doc = "Place a patrol dog of a known breed in a declared zone.",
      args = [
        entity_id "id",
        { name = "breed", type = 'string, domain = "dog_breeds" },
        entity_id "zone",
      ],
    },
    {
      name = "add_drone",
      collection = "drones",
      doc = "Place a drone of a known archetype in a declared zone.",
      args = [
        entity_id "id",
        { name = "archetype", type = 'string, domain = "drone_archetypes" },
        entity_id "zone",
      ],
    },
    {
      name = "add_npc",
      collection = "npcs",
      doc = "Place an ambient civilian NPC in a declared zone.",
      args = [
        entity_id "id",
        { name = "role", type = 'string, domain = "npc_roles" },
        entity_id "zone",
      ],
    },
    {
      name = "add_character",
      collection = "characters",
      doc = "Place a named character: an ActorArchetype + Modifier pair.",
      args = [
        entity_id "id",
        { name = "archetype", type = 'string, domain = "character_archetypes" },
        { name = "modifier", type = 'string, domain = "character_modifiers" },
        entity_id "zone",
      ],
    },
    {
      name = "add_item",
      collection = "items",
      doc = "Place an object/item of a known category in a declared zone.",
      args = [
        entity_id "id",
        { name = "category", type = 'string, domain = "item_categories" },
        entity_id "zone",
      ],
    },
    {
      name = "set_mission",
      collection = "mission",
      doc = "Set the mission block. Its internals remain game-owned.",
      args = [{ name = "mission", type = 'object }],
    },
    {
      name = "set_physical",
      collection = "physical",
      doc = "Set the physical-setup block. Its internals remain game-owned.",
      args = [{ name = "physical", type = 'object }],
    },
  ],

  # Derived views, so consumers never re-walk the registry by hand.

  # Verb name -> ordered argument names. This IS the positional order the
  # engine binds solve()'s arguments in.
  arg_order =
    std.array.fold_left
      (fun acc v => acc & { "%{v.name}" = std.array.map (fun a => a.name) v.args })
      {}
      verbs,

  # Verb name -> {argument name -> vocabulary members}. The finite domains
  # solve() may enumerate when an argument is left fresh.
  domains =
    std.array.fold_left
      (fun acc v =>
        acc
        & {
          "%{v.name}" =
            std.array.fold_left
              (fun m a =>
                if std.record.has_field "domain" a then
                  m & { "%{a.name}" = std.record.get a.domain vocab }
                else
                  m)
              {}
              v.args
        })
      {}
      verbs,

  names = std.array.map (fun v => v.name) verbs,
}
