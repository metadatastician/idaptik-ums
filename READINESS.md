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

**Current Grade:** D

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
| Idris2 ABI (`abi/`) | D | Alpha-unstable | 16 of the intended 17 modules typecheck under `idris-ci.yml`; ProvenBridge (the 17th) is still in flight with 2 typed holes. **This is what holds the project line at D.** | 2026-07-22 |
| SPARK/GNATprove reference model (`spark/`) | X | — | Does not exist. Decided in ADR-0003 (§3) and not started; `gnatprove` is not installed on the development machine. | 2026-07-22 |
| Zig hexadeca connector | X | — | Does not exist. `ffi/zig/` is the existing 11-file C-ABI surface, not the 16-protocol unified connector. | 2026-07-22 |
| Interactive studio frontend | X | — | 0% — not started. The engine has no interactive consumer. Supersedes the former "AffineScript shell" row: IDApTIK uses Bevy, but UMS remains an independent authoring application and its portal is currently a design reference. | 2026-07-25 |
| Reversible VM (`dlc/vm/`, `.affine`) | X | — | Has never compiled. No AffineScript toolchain is wired to this repo; the `.affine` sources have never been exercised by anything, so its declared `every-instruction-has-an-inverse` guarantee has never been checked. | 2026-07-22 |

## Why Grade D — for a much narrower reason than before

CRG defines the project line as the grade of the worst deployed component. It
is still **D**, but the reason has changed completely.

The 2026-07-20 assessment was held at D by three things: the engine was Python
with no CI, the DLC schema check ran local-only, and the ABI was 16/17. **Two
of the three are now resolved.** The engine and the validator are Rust, CI-
gated, with profile, engine and package negative tests proving the gates can
fail. What remains is:

- **`abi/ProvenBridge.idr`** — 2 typed holes and a commented-out `proven`
  dependency. One D-graded deployed component sets the line. Landing it, or
  formally descoping it, moves the project to C.
- **Not X or E:** every component above the D-line runs real, failing-able
  tests that currently pass, with documented scope.
- The X-graded components (frontends, SPARK model, hexadeca connector, VM) are
  not deployed and gate nothing — but they are why this cannot claim more than
  alpha-unstable, because the studio still has no interactive surface and the
  VM has never compiled.

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
- The UMS → game round trip has never been executed end to end. Both sides
  validate against the same declared contract, but nothing proves the game
  accepts what UMS emits.
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

- **PROJECT D → C:** land `ProvenBridge` or formally descope it (the STATE.a2ml
  "fate decision"), so the module-count claim and the tree agree. This is the
  single remaining blocker on the project line.
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
