<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->

# idaptik-ums Component Readiness Assessment

**Standard:** [Component Readiness Grades (CRG) v2.0](https://github.com/hyperpolymath/standards/tree/main/component-readiness-grades)
**Assessed:** 2026-07-20
**Assessor:** Claude (PR E of the staged lineage migration), from real local runs
and the repo's CI workflows — evidence over intuition, no aspirational grading.

**Current Grade:** D

## Summary

| Component | Grade | Release stage | Evidence summary | Last assessed |
|---|---|---|---|---|
| ai-edit engine (`ai_edit/`, Python) | D | Alpha-unstable | 37 unit tests + sample edit-script replay green locally (`just test`, `just ai-edit-check`). No CI workflow runs them yet, and the engine has no real consumer (the shell that would drive it is 0%). | 2026-07-20 |
| Zig FFI (`ffi/zig/`) | C | Alpha-stable | 24/24 integration tests pass; CI-gated (`zig-ci.yml`); zig 0.14.0 pin enforced locally by `_zig-guard` and in CI. | 2026-07-20 |
| Idris2 ABI (`abi/`) | D | Alpha-unstable | 16 of the intended 17 modules typecheck under `idris-ci.yml` (`idris2 --typecheck idaptik-ums.ipkg`); ProvenBridge (the 17th) is still in flight with 2 typed holes. | 2026-07-20 |
| DLC bridge (`schemas/` + `scripts/validate_dlc.py`) | D | Alpha-unstable | `just dlc-check` validates all 30 in-tree DLC artifacts against the bridge schemas; CI covers only JSON well-formedness (`puzzle-data.yml`) — full schema validation is local-only. | 2026-07-20 |
| Licence hygiene gate | C | Alpha-stable | `licence-hygiene.yml` gates every push/PR; it exists because it caught a real defect (dlc/vm carried the AGPL body under an MPL-2.0 SPDX header, fixed in PR #6). | 2026-07-20 |
| AffineScript shell | X | — | 0% — the port from the lineage ReScript tree has not started. Nothing exists to test. | 2026-07-20 |
| Reversible VM (`dlc/vm/`, `.affine`) | X | — | Has never compiled. No AffineScript toolchain is wired to this repo; the `.affine` sources have never been exercised by anything. | 2026-07-20 |

## Why Grade D (not C, not X)

CRG defines the project line as the grade of the primary component / the worst
deployed component. The deployed, working surface of this repo — ai-edit
engine, Idris2 ABI, DLC bridge — sits honestly at **D (alpha-unstable)**:

- **Not C:** grade C requires CI-integrated validation and no known failures
  in the home context. The Python engine and the full DLC schema check run
  only via local `just` recipes; the ABI is 16/17 with ProvenBridge open; and
  governance CI on `main` is red (pre-existing, estate-wide — the
  `hyperpolymath/standards` reusable workflows it wraps `startup_failure`).
- **Not X or E:** every graded component above D-line runs real, failing-able
  tests that currently pass, with documented scope. That is exactly D:
  "works on some cases, but not systematically".
- The X-graded components (shell, VM) are not deployed and gate nothing, but
  they are why this project cannot honestly claim more than alpha-unstable:
  the architecture's top layer does not exist and the VM has never compiled.

## Known failures and debt (kept visible on purpose)

- `governance.yml` is red on `main` — pre-existing, estate-wide (thin wrapper
  over `hyperpolymath/standards` reusables that fail at startup). Not
  repo-local; fix is upstream.
- `push-email-notify.yml` is the estate-wide never-green template.
- Python is banned by the estate language policy; `ai_edit` landed as Python
  in the lineage migration and is un-migrated — an open policy conflict,
  listed here rather than hidden.
- RSR compliance is partial: `.machine_readable/6a2/` + contractiles are
  present, but `0-AI-MANIFEST.a2ml` is absent and no Immaculate Guide
  compliance evidence is recorded in STATE.a2ml (a formal Grade-D
  requirement for hyperpolymath projects — tracked as debt, not waived).
- Until 2026-07-20 the Justfile's `test-all` chained five echo-stubs and
  printed "safe to merge!". Those recipes are deleted; every remaining gate
  runs real work and can fail.

## Promotion paths

- **ai-edit D → C:** add a Python CI workflow running `just test`,
  `just ai-edit-check`, `just dlc-check`; grow a real consumer (the shell).
- **ABI D → C:** land ProvenBridge or formally descope it (the STATE.a2ml
  "fate decision"), so the module count claim and the tree agree.
- **DLC bridge D → C:** run `scripts/validate_dlc.py` (full schema check) in
  CI, not just the JSON-parse loop.
- **Shell X → D:** start the AffineScript port (`src/{App.res, editor/, abi/}`
  in the lineage repo is the source material).
- **VM X → D:** wire an AffineScript toolchain and make `dlc/vm` compile at
  all before claiming anything about reversibility.

## Machine-readable

The grade line near the top of this file (`Current Grade`) is parsed by
`just crg-grade` and `just crg-badge`; before this file existed both recipes
silently fell back to grade "X".
