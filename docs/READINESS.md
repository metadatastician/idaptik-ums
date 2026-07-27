<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->

# Universal Modding Studio Component Readiness Assessment

**Standard:** [Component Readiness Grades (CRG) v2.0](https://github.com/hyperpolymath/standards/tree/main/component-readiness-grades)
**Assessed:** 2026-07-25 (re-assessed for the profile realignment; previous
assessment 2026-07-22)
**Assessor:** Claude (PR E of the staged lineage migration), from real local runs
and the repo's CI workflows — evidence over intuition, no aspirational grading.

**Current Grade:** C  
*(was D until 2026-07-27; the blocker was a stale row, not the tree — see below)*

## Summary

| Component | Grade | Release stage | Evidence summary | Last assessed |
|---|---|---|---|---|
| Profile SDK (`crates/ums-profile-sdk`) | C | Alpha-stable | 8 tests cover registration, malformed ID/version rejection, reflection, fixtures, deterministic adapter behavior, duplicate refusal and two-way profile isolation. Both generated profile descriptors are validated at load. | 2026-07-25 |
| IDApTIK edit compatibility engine (`crates/ums-ai-edit`, Rust) | C | Alpha-stable | 61 tests (miniKanren kernel, verbs, six runtime relations, deterministic replay and explicit profile dispatch) + sample replay, gated by `rust-ci.yml` with `clippy -D warnings`. | 2026-07-25 |
| Package/DLC bridge (`crates/ums-dlc` + `schemas/`) | C | Alpha-stable | 39 tests; validates all in-tree artifacts, legacy-manifest compatibility, v1→v2 migration and capability declarations. | 2026-07-25 |
| Chronicles of Slavia profile | D | Design fixture | Reflection and isolation are tested against a minimal Zone A fixture; no UMS compiler, loader or runtime integration exists. | 2026-07-25 |
| Enaction adapter | X | Designed only | Typed preview seam and request schema exist; no real adapter or loader exists. | 2026-07-25 |
| Generation source of truth (`config/*.ncl`) | C | Alpha-stable | `config-check` typechecks every source AND requires all three `config/bad/bad_*.ncl` negative fixtures to be rejected; `gen-check` diffs generated artifacts and fails when `nickel` is absent rather than skipping. Gated by `config-gen.yml`. | 2026-07-22 |
| Zig FFI (`ffi/zig/`) | C | Alpha-stable | 24/24 integration tests pass; CI-gated (`zig-ci.yml`); zig 0.14.0 pin enforced locally by `_zig-guard` and in CI. | 2026-07-20 |
| Licence hygiene gate | C | Alpha-stable | Three steps, each negative-tested: a planted MPL header, a truncated LICENSE and an unattributed JSON file each make it fail. Polarity inverted with the AGPL relicence. | 2026-07-22 |
| Idris2 ABI (`abi/`) | C | Beta | All 17 modules typecheck under `idris-ci.yml`, including `ProvenBridge`; the extractor test executable passes 40/40. `%default total` in every module, no `believe_me`, `postulate` or `assert_total`. Caveat: CI builds against a `proven` with `Proven.SafeMath.Proofs` removed (upstream issue), disclosed in `scripts/proven-min.ipkg`. See `Validation.idr` below. | 2026-07-27 |
| SPARK/GNATprove reference model (`spark/`) | X | — | Does not exist. Decided in ADR-0003 (§3) and not started; `gnatprove` is not installed on the development machine. | 2026-07-22 |
| Zig hexadeca connector | X | — | Does not exist. `ffi/zig/` is the existing 11-file C-ABI surface, not the 16-protocol unified connector. | 2026-07-22 |
| Interactive studio frontend | X | — | 0% — not started. The engine has no interactive consumer. Supersedes the former "AffineScript shell" row: IDApTIK uses Bevy, but UMS remains an independent authoring application and its portal is currently a design reference. | 2026-07-25 |
| Reversible VM (`dlc/vm/`, `.affine`) | X | — | Has never compiled. No AffineScript toolchain is wired to this repo; the `.affine` sources have never been exercised by anything, so its declared `every-instruction-has-an-inverse` guarantee has never been checked. | 2026-07-22 |

## Why the grade moved D → C

CRG defines the project line as the grade of the worst deployed component. It
is still **D**, but the reason has changed completely.

The 2026-07-20 assessment was held at D by three things: the engine was Python
with no CI, the DLC schema check ran local-only, and the ABI was 16/17. **All
three are now resolved.** The engine and the validator are Rust, CI-gated, with
profile, engine and package negative tests proving the gates can fail.

`abi/ProvenBridge.idr` landed on 2026-07-20 (`c86c84c`) and its extractors on
2026-07-21 (`a8b7663`). It has no typed holes, `idaptik-ums.ipkg` declares
`depends = proven` uncommented, and `idris-ci.yml` has been green on every run
since 2026-07-22. **The D grade was held for five days by this table, not by
the tree** — the row was never re-run after the work landed. Re-assessed
2026-07-27 against a local reproduction of the CI pipeline: 17/17 modules
typecheck, extractor tests 40/40.

What remains:

- **`abi/Validation.idr` — closed 2026-07-27.** It previously declared six
  proof-witness types and a `ValidatedLevel` record with four erased proof
  fields, and contained **zero top-level function signatures** — no decision
  procedure constructed any witness, and `ValidatedLevel` appeared nowhere else
  in the repository. It typechecked because declaring a datatype always does.
  It now carries seven `Dec`-returning deciders, a `DecEq IpAddress` instance,
  and `validateLevel : LevelData -> Maybe ValidatedLevel`, which is the only
  route from raw level data to a validated one. Seven compile-time assertions
  pin decider behaviour so a decider that always answered `No` would fail the
  build. 15 top-level signatures, 0 holes, 0 escape hatches, `%default total`.

**Assessment basis.** The Rust and Nickel gates were verified by local runs of
the exact commands CI executes. `rust-ci.yml` and `config-gen.yml` are new
files whose first CI execution happens when their branches reach `main`; every
workflow here filters on `pull_request: branches: [main]`, so a stacked PR
does not trigger them. Graded on measured local evidence, with that caveat
stated rather than papered over.

## Known failures and debt (kept visible on purpose)

- `governance.yml` is red on `main` — pre-existing, estate-wide (thin wrapper
  over `hyperpolymath/standards` reusables that fail at startup). Not
  repo-local; fix is upstream.
- `push-email-notify.yml` is the estate-wide never-green template.
- ~~Python is banned by the estate language policy; `ai_edit` landed as
  Python~~ — **resolved 2026-07-22.** `ai_edit/`, `scripts/validate_dlc.py`
  and both test modules are deleted; `git ls-files '*.py'` is empty. ADR-0001
  is superseded by ADR-0003.
- Two of the six hand-maintained copies of the closed vocabularies are still
  hand-written: `abi/Types.idr` and `ffi/zig/src/types.zig`. They are checked
  by tests, not generated from `config/vocab.ncl` — the obvious next extension
  of `scripts/gen.sh`.
- ~~The UMS → game round trip has never been executed end to end.~~
  **Resolved 2026-07-27.** `just roundtrip-idaptik` compiles the profile
  source, IDApTIK's real loader accepts it, and the run snapshots, restores
  and replays identically. Gated in `rust-ci.yml` and observed green.
  Remaining gap, stated precisely: the gate proves acceptance and
  deterministic replay, not that authored state survived the trip — that
  needs `package-runner` to export the canonical `LevelData`. See
  `docs/ROUNDTRIP-STATUS.adoc`.
- `dlc/legacy-ts-puzzles/` carries a directory name from its
  ReScript/TypeScript origin. The 27 files are plain JSON; only the path is
  stale.
- RSR compliance is partial: `.machine_readable/6a2/` + contractiles are
  present, but `0-AI-MANIFEST.a2ml` is absent and no Immaculate Guide
  compliance evidence is recorded in STATE.a2ml (a formal Grade-D
  requirement for hyperpolymath projects — tracked as debt, not waived).
- Until 2026-07-20 the Justfile's `test-all` chained five echo-stubs and
  printed "safe to merge!". Those recipes are deleted; every remaining gate
  runs real work and can fail.

## Promotion paths

- **PROJECT D → C: done, 2026-07-27.** `ProvenBridge` landed on 2026-07-20 and
  the tree and the module-count claim now agree. No descope ADR is needed:
  descoping something that works would be the wrong record.
- **PROJECT C → B:** write `Dec`-returning deciders for the four invariants
  `Validation.idr` declares, so a `ValidatedLevel` can actually be constructed
  and the extractor path is obliged to produce one. This is real work — a few
  days — and unlike the phantom holes it is genuine.
- **ai-edit C → B:** grow a real consumer, and close the type-6 loop so the
  proposer consults `solve()` in-process rather than across a boundary.
- **DLC bridge C → B:** execute the round trip in CI — generate an artifact
  from UMS and load it with IDApTIK's loader.
- **SPARK model X → C:** add `spark/src/ums_zones.ads` per ADR-0003 §3, a
  parity test against `constraints.rs`, and a proof gate that **fails when
  `gnatprove` is absent** rather than exiting 0.
- **Frontends X → D:** start `ums-tui` (ratatui, headless so CI can drive it),
  mirroring `idaptik-tui`.
- **VM X → D:** port `dlc/vm` to Rust so it compiles at all, and make its
  `every-instruction-has-an-inverse` guarantee a round-trip property test over
  all 23 instructions, before claiming anything about reversibility.

## Machine-readable

The grade line near the top of this file (`Current Grade`) is parsed by
`just crg-grade` and `just crg-badge`; before this file existed both recipes
silently fell back to grade "X".
