<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->

# idaptik-ums

The Unified Modding Studio (UMS). Procedural-generation pipeline and integration libraries for idaptik characters, levels, objects, and DLC extensions.

## Architecture

This repository contains the core logic, engines, and bridge components for UMS content generation and validation. Based on the current repository state, the system is composed of several specialized subsystems:

### 1. Idris2 ABI (`abi/`)
A suite of 17 Idris2 modules providing dependent-type proofs for the game integration boundary and core structures.
- **Scope**: Primitives, Devices, Zones, Validation, and experimental `ProvenBridge`.
- **Packaging**: Managed via `idaptik-ums.ipkg`.

### 2. Zig FFI (`ffi/zig/`)
Zig-based C-ABI exports (built with Zig 0.14.0) that integrate the core data structures and proofs with host systems and the game itself.
- **Scope**: 11 source files translating Idris2 ABI modules into C-compatible interfaces, along with robust integration tests.

### 3. AI-Edit Engine (`ai_edit/`)
A Python-based procedural generation engine used for content authoring and modification.
- **Scope**: Features a miniKanren relational programming kernel, constraint solvers, and domain-specific verbs/vocabularies for programmatic asset editing.

### 4. DLC & VM (`dlc/`)
Assets and runtimes for executing and verifying DLC payloads.
- **`dlc/vm/`**: A 23-instruction reversible virtual machine written in AffineScript, ported from `idaptik-dlc-vm`.
- **`dlc/legacy-ts-puzzles/`**: Authored puzzle JSONs preserved from `idaptik-dlc-iky`.

### 5. Schemas & Validation (`config/`, `schemas/`, `scripts/`)
Contracts ensuring UMS-generated content conforms to the game's expectations.
- **Nickel Source of Truth**: Generative schemas defined in `config/*.ncl`.
- **Validation**: Python scripts (`scripts/validate_dlc.py`) check the `dlc-manifest.json` artifacts against the generated schemas.

## UMS↔game integration

UMS produces generated content as `dlc-manifest.json` artifacts in the same shape as AssetPack output. The game's existing DLC loader consumes them with no game-side code changes. 

The integration contract is declared via schemas (generated from Nickel definitions) and validated locally before delivery.

## Development & Testing

This project uses `just` as its command runner. Key recipes:
- `just build` — Build the Zig FFI (requires Zig 0.14.0).
- `just test` — Run the Python unit-test suite (ai_edit engine + DLC validator).
- `just dlc-check` — Schema validation of all `dlc/` artifacts.
- `just gen` / `gen-check` — Regenerate and verify JSON schemas from Nickel sources.
- `just test-all` — Run all gates (Python tests, DLC check, ai-edit replay, Zig FFI integration).

## License

AGPL-3.0-or-later for code, CC-BY-SA-4.0 for documentation.
