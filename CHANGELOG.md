<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
﻿# Changelog

## [Unreleased]

### Added
- AI-edit direct-entity rules (issue #4): `add_npc` (in-level house/street
  NPCs), `add_character` (named actors as ActorArchetype + Modifier) and
  `add_item` (placed objects) verbs, backed by new closed-world vocabularies
  (`NPC_ROLES`, `CHARACTER_ARCHETYPES`, `CHARACTER_MODIFIERS`,
  `ITEM_CATEGORIES` in `ai_edit/vocab.py`) and a sixth validity proof
  `items_in_zones`; `guards_in_zones` extended to cover NPCs and characters.
  Wired through `ai_edit/engine.py` `VERB_SPECS`, `schemas/edit-script.schema.json`,
  `scripts/validate_dlc.py` and the replayed sample
  `dlc/examples/ai-edit-sample/edit-script.json` (2026-07-20).
- UMS<->game bridge contracts: `schemas/dlc-manifest.schema.json` (envelope,
  incl. `scenario-definition` / `actor-pack` kinds with versioned
  `payload.format` tags) and `schemas/puzzle.schema.json` (register puzzles +
  vault sequences); ownership split documented in `schemas/README.adoc`
  (2026-07-10).
- `just dlc-check` smoke test (`scripts/validate_dlc.py`, stdlib-only):
  validates all 28 `dlc/` artifacts against the contracts, including
  cross-field invariants (2026-07-10).
- Initial scaffold (2026-04-30).

### Fixed
- `dlc/legacy-ts-puzzles/bonus_04_bit_rotation.json` was invalid JSON
  (JavaScript `0b10101010` binary literals); now `170` (2026-07-10).
- `dlc/vm/dlc-manifest.json` `$schema` pointed at the nonexistent
  `hyperpolymath/idaptik-game` repo; now points at this repo's schema
  (2026-07-10).
- `Justfile` project metadata still carried the `rsr-template-repo`
  placeholders (2026-07-10).

[Unreleased]: https://github.com/hyperpolymath/idaptik-ums/compare/HEAD...HEAD
