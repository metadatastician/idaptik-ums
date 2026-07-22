<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->

# idaptik-ums Component Readiness Assessment

**Standard:** [Component Readiness Grades (CRG) v2.0](https://github.com/hyperpolymath/standards/tree/main/component-readiness-grades)
**Assessed:** 2026-07-22 (re-assessed after the Rust migration; previous
assessment 2026-07-20)
**Assessor:** Claude (PR E of the staged lineage migration), from real local runs
and the repo's CI workflows — evidence over intuition, no aspirational grading.

**Current Grade:** C

## Summary

| Component | Grade | Release stage | Evidence summary | Last assessed |
|---|---|---|---|---|
| AI-edit engine (`crates/ums-ai-edit`, Rust) | C | Alpha-stable | 59 tests (miniKanren kernel, verbs, the six proofs, both engine directions) + sample edit-script replay, gated by `rust-ci.yml` with `clippy -D warnings`. Parity with the deleted Python was measured: identical proposals AND identical search order, byte-identical final state. CI carries a negative step — an out-of-vocabulary rank must be refused. | 2026-07-22 |
| DLC bridge (`crates/ums-dlc` + `schemas/`) | C | Alpha-stable | 37 tests; validates all 31 in-tree artifacts against manifest, puzzle, vault, edit-script and taxonomy contracts, now in CI (`rust-ci.yml`) rather than local-only. Parity fuzzed against the Python: 32/32 mutations, identical verdict and message. | 2026-07-22 |
| Generation source of truth (`config/*.ncl`) | C | Alpha-stable | `config-check` typechecks every source AND requires all three `config/bad/bad_*.ncl` negative fixtures to be rejected; `gen-check` diffs generated artifacts and fails when `nickel` is absent rather than skipping. Gated by `config-gen.yml`. | 2026-07-22 |
| Zig FFI (`ffi/zig/`) | C | Alpha-stable | 30/30 tests pass (24 integration + 6 hexadeca module tests); CI-gated (`zig-ci.yml`); zig 0.14.0 pin enforced locally by `_zig-guard` and in CI. | 2026-07-20 |
| Licence hygiene gate | C | Alpha-stable | Three steps, each negative-tested: a planted MPL header, a truncated LICENSE and an unattributed JSON file each make it fail. Polarity inverted with the AGPL relicence. | 2026-07-22 |
| Idris2 ABI (`abi/`) | C | Alpha-stable | **17 of 17 modules typecheck** (`idris2 --typecheck idaptik-ums.ipkg`, exit 0), ProvenBridge included; extractor tests execute the code rather than only typechecking it. `check-abi-trusted-base.sh` proves nothing widened the trusted base: 0 `believe_me`, 0 `assert_total`, 0 `assert_smaller`, 0 `idris_crash`, 0 `unsafePerformIO`, 0 `postulate`, and all 17 modules declare `%default total`. Negative-tested. | 2026-07-22 |
| SPARK/GNATprove reference model (`spark/`) | C | Alpha-stable | **Verification conditions discharged**: `gnatprove --level=2` (FSF 16.1.0) reports no unproved checks — 16/16 run-time checks, 6/6 assertions, and the postcondition proved. `just spark-parity` drives 26 shared vectors through the SPARK model and the Rust engine with identical verdicts. Both gates negative-tested; the proof gate fails when `gnatprove` is absent. | 2026-07-22 |
| Zig hexadeca connector | C | Alpha-stable | Wire contract built and gated: 16 connectors generated from `config/connectors.ncl` into Zig, Rust and Idris2, with 7 Rust tests proving cross-language ordinal agreement (negative-tested by swapping two Zig ordinals) and 6 Zig module tests executed under the pinned 0.14.0. **0 of 16 transports implemented**; `dispatch` returns `NotImplemented` for every tag rather than a success code. Graded on the wire contract, which is what exists; the transports are a separate, unstarted concern. | 2026-07-22 |
| Editor frontends (Bevy / Fyrox / TUI) | X | — | 0% — not started. The engine has no interactive consumer. Supersedes the former "AffineScript shell" row: the game is a Rust workspace with Bevy and Fyrox frontends, and the shell was never built. | 2026-07-22 |
| Reversible VM (`dlc/vm/`, `.affine`) | X | — | Has never compiled. No AffineScript toolchain is wired to this repo; the `.affine` sources have never been exercised by anything, so its declared `every-instruction-has-an-inverse` guarantee has never been checked. | 2026-07-22 |

## Why Grade C

CRG defines the project line as the grade of the worst deployed component.
Every deployed component is now **C (alpha-stable)**: CI-integrated
validation, no known failures in the home context.

The 2026-07-20 assessment was held at D by three things: the engine was Python
with no CI, the DLC schema check ran local-only, and the ABI was believed to
be 16/17 with ProvenBridge "still in flight with 2 typed holes". **All three
are resolved, and the third was never true by the time it was written.**

`abi/ProvenBridge.idr` was re-measured on 2026-07-22 rather than trusted:

```
$ idris2 --typecheck idaptik-ums.ipkg
 1/17: Building Primitives ... 17/17: Building Multiplayer
$ echo $?
0
```

Zero typed holes, zero escape hatches, `%default total` on all 17 modules. The
`proven` dependency landed with the six LevelData extractors (PR #14); the
"2 typed holes" line simply outlived the fact. It is now gated by
`check-abi-trusted-base.sh`, so it cannot silently regress — and typechecking
alone would not have caught a regression, because a module can typecheck while
using `believe_me`.

- **Not B:** grade B needs a real consumer and sustained use. The studio has no
  interactive surface, and the UMS → game round trip has never been executed.
- **Not D:** no deployed component has known failures or uncovered validation.
- The X-graded components (frontends, SPARK model, hexadeca connector, VM) are
  not deployed and gate nothing. They cap the ceiling, not the floor.

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

- **PROJECT C → B:** grow a real consumer (an editor frontend), and execute
  the UMS → game round trip in CI. Those are the two things separating
  "every gate is green" from "someone uses this".
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
