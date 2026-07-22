<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
﻿# Changelog

## [Unreleased]

### Changed
- **Relicensed to `AGPL-3.0-or-later` (code) and `CC-BY-SA-4.0` (documentation)**
  from MPL-2.0, so the studio and the AGPL game it mods share a licence.
  MPL-2.0 §3.3 names AGPLv3 a Secondary License, making this the permitted
  direction; a provenance sweep found no third-party copyright. All 116
  headers normalised to the two-line SPDX form; `REUSE.toml` covers the JSON
  files that cannot carry one. `licence-hygiene.yml` polarity inverted in the
  same commit, because it failed the build on any AGPL declaration (2026-07-22).
- **`config/*.ncl` (Nickel) is now the single source of truth** for the closed
  vocabularies and the verb registry, generating `schemas/edit-script.schema.json`
  and the Rust registry. They were previously hand-maintained in six places
  (2026-07-22).
- **The AI-edit engine is Rust** (`crates/ums-ai-edit`), replacing the
  `ai_edit/` Python package. The miniKanren kernel was hand-ported; parity was
  measured before deletion — identical proposals *and* identical search order,
  byte-identical final state on the shipped sample (2026-07-22).
- **The DLC validator is Rust** (`crates/ums-dlc`), replacing
  `scripts/validate_dlc.py`, and shares the generated vocabularies with the
  engine so the two cannot disagree. Parity fuzzed: 32/32 mutations, identical
  verdict and message (2026-07-22).
- Documentation rewritten against the tree: the README's *AffineScript shell
  over a Gossamer host runtime, ported from ReScript* was never built, and the
  game is a Rust workspace with Bevy and Fyrox frontends. `EXPLAINME.adoc`
  added; `READINESS.md` regraded; ADR-0001 superseded by ADR-0003 (2026-07-22).

### Fixed
- `dlc/examples/ai-edit-sample/dlc-manifest.json` declared
  `verification.replay = "python3 -m ai_edit check …"`, a machine-readable
  evidence pointer to a deleted command (2026-07-22).
- `add_zone`'s optional `segment` argument was domain-constrained even when
  absent, which would have made every segment-less `add_zone` unsatisfiable —
  found by the Rust port (2026-07-22).
- Template self-name leak: the contractiles and several `Justfile` recipes
  declared this repository to be `rsr-template-repo` (2026-07-22).
- `.machine_readable/6a2/STATE.a2ml` listed a *critical* todo to rewrite the
  docs "to Gossamer", a runtime the game does not use (2026-07-22).

### Removed
- All Python. `git ls-files '*.py'` is empty: `ai_edit/` (7 modules),
  `scripts/validate_dlc.py`, both test modules and 9 committed `.pyc` files
  (2026-07-22).
- `.github/workflows/puzzle-data.yml`, folded into `rust-ci.yml`, which
  validates every artifact against the full bridge contracts rather than
  running `json.load` over one directory (2026-07-22).

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
- `dlc/legacy-puzzles/bonus_04_bit_rotation.json` was invalid JSON
  (JavaScript `0b10101010` binary literals); now `170` (2026-07-10).
- `dlc/vm/dlc-manifest.json` `$schema` pointed at the nonexistent
  `hyperpolymath/idaptik-game` repo; now points at this repo's schema
  (2026-07-10).
- `Justfile` project metadata still carried the `rsr-template-repo`
  placeholders (2026-07-10).

[Unreleased]: https://github.com/hyperpolymath/idaptik-ums/compare/HEAD...HEAD
