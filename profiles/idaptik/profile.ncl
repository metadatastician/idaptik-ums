# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# IDApTIK profile reflection. The established vocabularies and verbs remain
# sourced from config/*.ncl during the compatibility stage.

let vocab = import "../../config/vocab.ncl" in
let verbs = import "../../config/verbs.ncl" in
let vocabulary_id = fun domain =>
  if domain == "device_kinds" then "device-kinds"
  else if domain == "guard_ranks" then "guard-ranks"
  else if domain == "dog_breeds" then "dog-breeds"
  else if domain == "drone_archetypes" then "drone-archetypes"
  else if domain == "wiring_types" then "wiring-types"
  else if domain == "npc_roles" then "npc-roles"
  else if domain == "character_archetypes" then "character-archetypes"
  else if domain == "character_modifiers" then "character-modifiers"
  else if domain == "item_categories" then "item-categories"
  else if domain == "zone_segments" then "zone-segments"
  else domain
in
let value_type = fun ty =>
  if ty == 'string then "string"
  else if ty == 'integer then "integer"
  else if ty == 'number then "number"
  else if ty == 'object then "object"
  else "unknown"
in
let field = fun arg =>
  {
    id = arg.name,
    valueType = value_type arg.type,
    vocabulary =
      if std.record.has_field "domain" arg then
        vocabulary_id arg.domain
      else
        null,
    required =
      if std.record.has_field "required" arg then arg.required else true,
  }
in
{
  apiVersion = "ums-profile/1",
  profileId = "idaptik",
  version = "1.0.0",
  targetGame = {
    id = "idaptik",
    name = "IDApTIK",
    compatibleVersions = ["0.x"],
  },
  vocabularies = {
    "device-kinds" = vocab.device_kinds,
    "guard-ranks" = vocab.guard_ranks,
    "dog-breeds" = vocab.dog_breeds,
    "drone-archetypes" = vocab.drone_archetypes,
    "wiring-types" = vocab.wiring_types,
    "npc-roles" = vocab.npc_roles,
    "character-archetypes" = vocab.character_archetypes,
    "character-modifiers" = vocab.character_modifiers,
    "item-categories" = vocab.item_categories,
    "zone-segments" = vocab.zone_segments,
  },
  componentTypes = [
    {
      id = "spatial.zone",
      label = "Zone",
      fields = [
        { id = "id", valueType = "string", vocabulary = null, required = true },
        { id = "securityTier", valueType = "integer", vocabulary = null, required = true },
        { id = "segment", valueType = "string", vocabulary = "zone-segments", required = false },
      ],
    },
    {
      id = "systems.device",
      label = "Device",
      fields = [
        { id = "id", valueType = "string", vocabulary = null, required = true },
        { id = "kind", valueType = "string", vocabulary = "device-kinds", required = true },
        { id = "zone", valueType = "string", vocabulary = null, required = true },
        { id = "worldX", valueType = "number", vocabulary = null, required = true },
      ],
    },
    {
      id = "actors.guard",
      label = "Guard",
      fields = [
        { id = "id", valueType = "string", vocabulary = null, required = true },
        { id = "rank", valueType = "string", vocabulary = "guard-ranks", required = true },
        { id = "zone", valueType = "string", vocabulary = null, required = true },
      ],
    },
    {
      id = "actors.dog",
      label = "Dog",
      fields = [
        { id = "id", valueType = "string", vocabulary = null, required = true },
        { id = "breed", valueType = "string", vocabulary = "dog-breeds", required = true },
        { id = "zone", valueType = "string", vocabulary = null, required = true },
      ],
    },
    {
      id = "actors.drone",
      label = "Drone",
      fields = [
        { id = "id", valueType = "string", vocabulary = null, required = true },
        { id = "archetype", valueType = "string", vocabulary = "drone-archetypes", required = true },
        { id = "zone", valueType = "string", vocabulary = null, required = true },
      ],
    },
    { id = "actors.assassin", label = "Assassin", fields = [] },
    { id = "actors.npc", label = "Ambient NPC", fields = [] },
    { id = "actors.character", label = "Named character", fields = [] },
    { id = "items.item", label = "Item", fields = [] },
    {
      id = "systems.wiring",
      label = "Wiring run",
      fields = [
        { id = "type", valueType = "string", vocabulary = "wiring-types", required = true },
        { id = "from", valueType = "string", vocabulary = null, required = true },
        { id = "to", valueType = "string", vocabulary = null, required = true },
      ],
    },
    { id = "spatial.zone-transition", label = "Zone transition", fields = [] },
    { id = "systems.device-defence", label = "Device defence", fields = [] },
    {
      id = "systems.pbx",
      label = "PBX configuration",
      fields = [
        { id = "hasPBX", valueType = "boolean", vocabulary = null, required = true },
        { id = "pbxIp", valueType = "string", vocabulary = null, required = false },
        { id = "pbxWorldX", valueType = "number", vocabulary = null, required = false },
      ],
    },
    { id = "missions.mission", label = "Mission block", fields = [] },
    { id = "world.physical", label = "Physical block", fields = [] },
  ],
  editVerbs =
    std.array.map
      (fun verb => {
        id = verb.name,
        collection = verb.collection,
        summary = verb.doc,
        arguments = std.array.map field verb.args,
      })
      verbs.verbs,
  constraints = [
    { id = "guards-in-zones", version = "1" },
    { id = "defence-targets", version = "1" },
    { id = "zones-ordered", version = "1" },
    { id = "pbx-consistent", version = "1" },
    { id = "devices-exist", version = "1" },
    { id = "items-in-zones", version = "1" },
  ],
  capabilities = [
    "spatial.zones",
    "actors.security",
    "actors.characters",
    "systems.network-topology",
    "systems.pbx",
    "missions.blocks",
    "physical.blocks",
    "edit.replay",
  ],
  generators = [{ id = "relational-edit-solver", version = "1" }],
  importers = [{ id = "idaptik-level", format = "idaptik-level/1" }],
  exporters = [{ id = "idaptik-edit", format = "idaptik-edit/1" }],
  inspectors = [
    { id = "idaptik.network-inspector", label = "Network topology", applies_to = ["systems.device", "systems.wiring"] },
    { id = "idaptik.pbx-inspector", label = "PBX", applies_to = ["systems.pbx"] },
  ],
  canvasLenses = [
    { id = "idaptik.security-lens", label = "Security", applies_to = ["spatial.zone", "actors.guard", "systems.device"] },
  ],
  simulationAdapter = null,
  packageCompiler = { id = "idaptik-package-compiler", version = "1" },
  runtimeContract = { id = "idaptik-level", version = "1" },
  migrations = [{ from = "idaptik-edit/1", to = "idaptik-edit/1", id = "identity-v1" }],
  tests = [
    { id = "idaptik-edit-engine-contracts", version = "1" },
    { id = "idaptik-dlc-contracts", version = "1" },
  ],
  guarantees = [
    { id = "immutable-state-transitions", level = "tested", evidence = "crates/ums-ai-edit/tests/engine.rs" },
    { id = "deterministic-edit-replay", level = "tested", evidence = "crates/ums-ai-edit/tests/engine.rs" },
    { id = "idris2-abi-types", level = "machine-checked", evidence = "abi/" },
    { id = "profile-runtime-roundtrip", level = "aspirational", evidence = "docs/ROUNDTRIP-STATUS.adoc" },
  ],
}
