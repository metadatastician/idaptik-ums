<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk> -->

# Contributing to Universal Modding Studio

Thanks for your interest. This repository follows the Hyperpolymath estate
standards defined in [hyperpolymath/standards](https://github.com/hyperpolymath/standards).

## Licence

This project is licensed under **AGPL-3.0-or-later** (code) and **CC-BY-SA-4.0** (documentation). By contributing you agree that
your contributions are licensed under the same terms. Every source file
carries an `SPDX-License-Identifier` header; keep it when editing, and add
one to any new file.

## Development environment

A pinned dev shell is provided:

```sh
nix develop        # toolchain: just
```

Estate policy is Guix primary / Nix fallback; this repo currently ships the
Nix fallback. A `guix.scm` is welcome if you prefer the primary tier.

## Build and test

This repo uses [`just`](https://just.systems) (the estate uses Justfiles,
never Makefiles). Recipes available here:

```sh
just            # list recipes
just fmt        # format
just fmt-check  # check formatting
just lint       # lint
just test-all   # run the full suite
just doctor     # environment diagnostics
```

## Machine-readable artefacts

This repo carries `.machine_readable/` A2ML files (`STATE.a2ml`,
`META.a2ml`, `ECOSYSTEM.a2ml`, `AGENTIC.a2ml`, `NEUROSYM.a2ml`,
`PLAYBOOK.a2ml`). If your change alters project state, architecture, or
operational steps, update the corresponding file in the same PR — CI
validates them.

## Language policy

The estate restricts which languages may be used. In particular Python, Go,
TypeScript, ReScript, V-lang, Java/Kotlin, Swift and Makefiles are **not**
accepted in new code; AffineScript, Rust/SPARK, Zig, Nickel, Deno, Gleam,
Elixir, Haskell, Idris2, Agda, Julia and OCaml are. CI enforces this, so check
the policy in `hyperpolymath/standards` before introducing a new language.

What this repo actually uses: **Rust** for the engine and the bridge
validator, **Nickel** for generation, **Idris2** for the ABI proofs, **Zig**
for the C-ABI FFI, **`just`** as the task runner. `ai_edit/` was Python — an
exception that lasted months — and was removed on 2026-07-22 (ADR-0003).
Adding a generated file by hand fails `just gen-check`; adding a vocabulary
anywhere but `config/vocab.ncl` fails `just ai-edit-reflect`.

Game-specific vocabulary belongs under `profiles/<profile-id>`. Do not add
IDApTIK or Chronicles of Slavia concepts to a universal namespace. A new
crate must contain a real responsibility, code and tests; destination-layout
placeholders are not accepted.

## Documentation format

Docs are AsciiDoc (`.adoc`) by default. `README.md` and `READINESS.md` are
deliberate Markdown exceptions (GitHub renders them as the repository front
page and the CRG grade line is parsed from `READINESS.md`). The
GitHub-required community-health files stay Markdown: `SECURITY.md`,
`CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `CHANGELOG.md`. Do not add a `.md`
duplicate of a doc that already exists as `.adoc`.

## Pull requests

1. Branch from `main` — do not push to `main` directly; branch protection
   requires review and passing checks.
2. Keep the change focused, and explain *why* in the PR body.
3. Make sure governance CI is green. It checks documentation presence,
   packaging policy, secrets, licence consistency and workflow security.
4. Security issues: follow `SECURITY.md` — report privately, never in a
   public issue.
