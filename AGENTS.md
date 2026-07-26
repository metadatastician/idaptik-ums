<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk> -->

# Universal Modding Studio agent instructions

- Preserve repository history, formal machinery, generated sources, DLC and
  provenance. Never recreate the repository to rename it.
- The product is Universal Modding Studio (UMS). IDApTIK and Chronicles of
  Slavia are profiles, not aliases for the core.
- Keep game nouns and doctrine under `profiles/<profile-id>` or an explicit
  compatibility facade. Do not put PBX, security ranks, the Rift, living
  taxis, remedies or heroine-specific vocabulary in universal namespaces.
- `config/*.ncl` remains the source of truth for the working IDApTIK registry.
  Run `just gen`; never hand-edit generated profile JSON or generated
  `crates/ums-ai-edit/src/vocab.rs`.
- Add a crate only with real implementation and tests. Prefer staged
  compatibility re-exports to a mass move.
- Label guarantees accurately: machine-checked, runtime-validated, tested,
  designed or aspirational.
- Before claiming completion run generation drift, Rust format/clippy/tests,
  DLC validation, Zig/Idris gates where available, and repository identity
  searches.
- The separate `metadatastician/chronicles-of-slavia` repository is the
  authority for Slavia design.
