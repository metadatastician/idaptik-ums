<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
﻿# Changelog

## [Unreleased]

### Added
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
