# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

{
  apiVersion = "ums-profile/1",
  profileId = "chronicles-of-slavia",
  version = "0.1.0",
  targetGame = {
    id = "chronicles-of-slavia",
    name = "Chronicles of Slavia",
    compatibleVersions = ["first-zone-design"],
  },
  vocabularies = {
    "heroine-influences" = ["Quickening", "Settling"],
    "world-disruptions" = ["RiftCorruption", "Inversion", "Severance"],
    "environmental-receptivity" = ["Receptive", "Guarded", "Dormant", "Wounded"],
    "place-memory-kinds" = ["Care", "Courage", "Loss", "Folklore", "Medicine"],
    "response-rule-kinds" = ["Natural", "RiftCorrupted"],
    "nature-kinds" = ["Natural"],
    "cooperation-modes" = ["Alternating", "Simultaneous", "Preparatory"],
  },
  componentTypes = [
    {
      id = "world.mythic-landscape-zone",
      label = "Mythic landscape zone",
      fields = [
        { id = "id", valueType = "string", vocabulary = null, required = true },
        { id = "receptivity", valueType = "string", vocabulary = "environmental-receptivity", required = true },
      ],
    },
    {
      id = "world.living-entity",
      label = "Autonomous living entity",
      fields = [
        { id = "id", valueType = "string", vocabulary = null, required = true },
        { id = "nature", valueType = "string", vocabulary = "nature-kinds", required = true },
        { id = "responseRule", valueType = "string", vocabulary = "response-rule-kinds", required = true },
      ],
    },
    { id = "world.environmental-receptivity", label = "Environmental receptivity", fields = [] },
    {
      id = "world.influence",
      label = "Quickening or settling influence",
      fields = [
        { id = "kind", valueType = "string", vocabulary = "heroine-influences", required = true },
        { id = "present", valueType = "boolean", vocabulary = null, required = true },
      ],
    },
    { id = "world.natural-response-rule", label = "Natural response rule", fields = [] },
    { id = "world.rift-response-rule", label = "Rift-corrupted response rule", fields = [] },
    {
      id = "world.place-memory",
      label = "Place memory",
      fields = [
        { id = "place", valueType = "string", vocabulary = null, required = true },
        { id = "kind", valueType = "string", vocabulary = "place-memory-kinds", required = true },
      ],
    },
    {
      id = "systems.bridge-stability",
      label = "Bridge stability",
      fields = [
        { id = "bridge", valueType = "string", vocabulary = null, required = true },
        { id = "stable", valueType = "boolean", vocabulary = null, required = true },
      ],
    },
    { id = "world.shrine-interaction", label = "Shrine interaction", fields = [] },
    { id = "actors.cooperation", label = "Two-character cooperation", fields = [] },
    { id = "missions.zone-a-objective", label = "Zone A objective", fields = [] },
  ],
  editVerbs = [
    {
      id = "declare_mythic_zone",
      collection = "mythicZones",
      summary = "Declare a bounded mythic landscape zone.",
      arguments = [
        { id = "id", valueType = "string", vocabulary = null, required = true },
        { id = "receptivity", valueType = "string", vocabulary = "environmental-receptivity", required = true },
      ],
    },
    {
      id = "add_living_entity",
      collection = "livingEntities",
      summary = "Add an autonomous animal or other living entity with its own natural response.",
      arguments = [
        { id = "id", valueType = "string", vocabulary = null, required = true },
        { id = "zone", valueType = "string", vocabulary = null, required = true },
      ],
    },
    {
      id = "set_place_memory",
      collection = "placeMemories",
      summary = "Record what a place remembers without reducing it to a scalar alignment.",
      arguments = [
        { id = "place", valueType = "string", vocabulary = null, required = true },
        { id = "kind", valueType = "string", vocabulary = "place-memory-kinds", required = true },
      ],
    },
    {
      id = "stabilise_bridge",
      collection = "bridgeStability",
      summary = "Describe cooperation that stabilises the first bridge metaphor.",
      arguments = [
        { id = "bridge", valueType = "string", vocabulary = null, required = true },
        { id = "mode", valueType = "string", vocabulary = "cooperation-modes", required = true },
      ],
    },
  ],
  constraints = [
    { id = "living-entities-have-natural-agency", version = "design-1" },
    { id = "rift-rules-transform-not-replace-nature", version = "design-1" },
    { id = "bridge-requires-two-character-cooperation", version = "design-1" },
  ],
  capabilities = [
    "world.mythic-landscape",
    "world.place-memory",
    "actors.autonomous-animals",
    "systems.natural-response",
    "systems.rift-corruption",
    "systems.bridge-stability",
    "narrative.folklore",
    "narrative.moral-choice",
    "missions.zone-a",
  ],
  generators = [],
  importers = [],
  exporters = [],
  inspectors = [
    { id = "slavia.place-memory", label = "Place memory", applies_to = ["world.mythic-landscape-zone", "world.place-memory"] },
  ],
  canvasLenses = [
    { id = "slavia.receptivity-lens", label = "Environmental receptivity", applies_to = ["world.mythic-landscape-zone", "world.living-entity"] },
  ],
  simulationAdapter = null,
  packageCompiler = null,
  runtimeContract = null,
  migrations = [],
  tests = [{ id = "zone-a-profile-fixture", version = "1" }],
  guarantees = [
    { id = "profile-isolation", level = "tested", evidence = "crates/ums-profile-sdk/tests/profiles.rs" },
    { id = "runtime-integration", level = "aspirational", evidence = "profiles/chronicles-of-slavia/README.adoc" },
  ],
}
