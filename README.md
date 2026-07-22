<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->

# idaptik-ums — the Unified Modding Studio

The modding studio for [IDApTIK](https://github.com/metadatastician/IDApTIK):
a procedural-generation pipeline for characters, levels, objects and DLC
extensions.

Its distinguishing feature is that **an AI can take direct action on a level**
— add a guard, place a device, wire a PBX — without ever being trusted to get
it right. Every edit is completed *and* checked by a relational engine before
it reaches the wire.

## Status, honestly

This README describes what is in the tree. Components that do not exist yet
are marked, not implied. Per-component grades and evidence are in
[READINESS.md](READINESS.md).

| Layer | State |
|---|---|
| AI-edit engine (`crates/ums-ai-edit`) | **built** — 59 tests, CI-gated |
| DLC bridge validator (`crates/ums-dlc`) | **built** — 37 tests, CI-gated |
| Generation source of truth (`config/*.ncl`) | **built** — CI-gated |
| Idris2 ABI (`abi/`) | **built** — 17/17 modules typecheck, trusted base gated |
| Zig FFI (`ffi/zig/`) | **built** — 24/24 tests, CI-gated |
| SPARK/GNATprove reference model (`spark/`) | *not started* |
| Zig hexadeca connector | *not started* |
| Editor frontends (Bevy / Fyrox / TUI) | *not started* |
| Reversible VM (`dlc/vm/`, AffineScript) | *has never compiled* |

## Architecture

```
                config/*.ncl — Nickel, the single source of truth
                       │ generates (diff-gated, never hand-edited)
      ┌────────────────┼────────────────┬──────────────────┐
      ▼                ▼                ▼                  ▼
 JSON Schemas    Rust registry     Idris2 vocab       Zig enums
 (schemas/)      + vocabularies    (abi/)             (ffi/zig/)

                   Rust workspace (AGPL-3.0-or-later)
 ums-ai-edit   miniKanren kernel · verbs · validity proofs · solve()
 ums-dlc       the UMS ↔ game bridge contract checker

 abi/          Idris2 dependent-type proofs of the ABI boundary
 ffi/zig/      Zig C-ABI exports
```

### The languages, and why each is here

- **Rust** owns the executable surface — the relational engine and the bridge
  validator. `#![forbid(unsafe_code)]`.
- **Nickel** owns generation. The closed vocabularies and the verb registry
  are declared once, in `config/vocab.ncl` and `config/verbs.ncl`; the JSON
  Schemas and the Rust registry are generated from them. They were previously
  hand-maintained in six places.
- **Idris2** owns the ABI proofs (`abi/`, 17 modules).
- **Zig** owns the C-ABI FFI (`ffi/zig/`). No C is written where Zig lives.
- **`just`** is the single task-runner entry point — `just --list`.

Python, TypeScript, ReScript and Go are not used, and
`.machine_readable/6a2/AGENTIC.a2ml` forbids them. JavaScript is avoided.

> **Stale claims removed 2026-07-22.** Earlier revisions of this file
> described an *AffineScript shell over a Gossamer host runtime*, ported from
> ReScript, and the wider docs mentioned Tauri. None of it was ever built
> here, and the game is a Rust workspace with **Bevy** and **Fyrox**
> frontends. Believing the old diagram would have meant porting to a runtime
> the game does not use.

## AI-edit: how an AI edits a level without being trusted

Design: [`docs/adr/0003-ai-edit-rust-minikanren-spark.adoc`](docs/adr/0003-ai-edit-rust-minikanren-spark.adoc),
which supersedes ADR-0001.

The engine is a Kautz **type-6** neurosymbolic system over a miniKanren
relational kernel. The symbolic engine sits *inside* the proposer's action
loop rather than downstream of it:

1. The proposer emits a **partial** edit —
   `{"verb":"add_guard","id":"g1","rank":"?","zone":"?"}`. Each `"?"` marks an
   argument the kernel must supply.
2. The kernel conjoins the finite-domain relations, the verb relation and all
   six validity proofs into **one search**.
3. Only edits with a satisfying model come back.

This is **generate-and-narrow**, not generate-then-filter: an
out-of-vocabulary value is never generated in the first place, and an edit
that would break an invariant is never proposed.

```console
$ cargo run -p ums-ai-edit -- solve \
    '{"verb":"add_guard","id":"g1","rank":"?","zone":"?"}' --state level.json -n 3
```

The six validity proofs, re-expressed from the archive editor's Idris2 proofs:
`guards-in-zones`, `defence-targets`, `zones-ordered`, `pbx-consistent`,
`devices-exist`, `items-in-zones`.

**Honest caveat.** What runs today is the kernel plus an LLM calling `solve()`
across a process boundary — operationally closer to type 2/3. Type 6 is the
target architecture the seam is shaped for: the kernel's API is already "goal
in, models out", so tightening the loop changes integration depth, not
contracts.

## Reflective, and gated on it

The engine describes itself, and CI proves the description is true:

```console
$ cargo run -p ums-ai-edit -- describe   # registry, vocabularies, proofs, guarantees
$ just ai-edit-reflect                   # compiled registry == the Nickel that generated it
```

Edit scripts are **homoiconic**: the wire format is the same shape the
engine's relations consume. An edit is therefore data — replayable, reviewable
in a pull request, and its own audit log.

## Integration with IDApTIK

UMS integrates with the game through **artifacts, not a Cargo dependency**, so
neither repo's CI can break the other:

- `dlc-manifest.json` envelopes, which the game's existing DLC loader consumes
  with no game-side code changes;
- the `idaptik-ffi` C ABI (JSON in, JSON out);
- shared Nickel schemas.

Both repos are `AGPL-3.0-or-later`, so tighter coupling is available if it is
ever wanted.

## The ABI, and what "proved" is allowed to mean

All 17 Idris2 modules typecheck, `ProvenBridge` included — it wires the real
`proven` dependency and the six `LevelData` extractors, and the extractor
tests *execute* that code rather than only typechecking it.

Typechecking alone would not be worth much. A module can typecheck while
cheating: `believe_me` coerces between any two types, `assert_total` silences
the totality checker, `%default partial` turns it off wholesale. So the ABI's
trusted base is stated explicitly and gated:

```console
$ just proof-check-abi
modules:        17 declared, all present and checked
escape hatches: none (believe_me, assert_total, assert_smaller, idris_crash, unsafePerformIO, postulate)
totality:       all 17 modules declare %default total
```

The gate is negative-tested: a planted `believe_me`, an undeclared module in
`abi/`, and a commented-out `%default total` each make it fail.

## Quick start

```console
$ just deps          # fails loudly if cargo / nickel / jq / zig are missing
$ just test-all      # every real gate
```

`just test-all` chains only recipes that do real work and can fail:
`test` · `config-check` · `gen-check` · `dlc-check` · `ai-edit-check` ·
`ai-edit-reflect` · `test-ffi`.

To change a vocabulary, edit `config/vocab.ncl` and run `just gen`. Editing a
generated file by hand fails `just gen-check`.

## Licence

`AGPL-3.0-or-later` for code, `CC-BY-SA-4.0` for documentation. Full texts in
[`LICENSES/`](LICENSES/); files that cannot carry a header are declared in
[`REUSE.toml`](REUSE.toml).
