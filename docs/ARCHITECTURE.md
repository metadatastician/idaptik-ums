<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk> -->

# Universal Modding Studio architecture

Universal Modding Studio is an independent authoring, generation, validation
and packaging platform for game worlds, systems, agents, narratives and rules.

## Dependency direction

```text
studio/CLI/LLM interface
        |
        v
host-neutral orchestration, IR, edit, solver, validation and package seams
        |
        v
ums-profile-sdk  <--- profile reflection + typed services
        |
        +---- profiles/idaptik
        |          |
        |          +---- IDApTIK package/runtime contracts
        |
        +---- profiles/chronicles-of-slavia
                   |
                   +---- future Slavia package/runtime contracts

optional preview adapter: UMS model -> profile translation -> Enaction contract
released runtime: compiled game package -> game loader/runtime
```

The core never depends on a game profile. A profile depends on the SDK
contract. A simulation adapter depends on host-neutral model/trace contracts
and a profile-supplied translation; it does not own game ontology. Enaction
Engine does not depend on the UMS application. Released games do not load the
editor UI.

Forbidden cycles:

- UMS Core → IDApTIK or Slavia ontology;
- UMS Core → Enaction Engine;
- Enaction Engine → UMS application;
- profile SDK → a particular profile;
- adapter → hard-coded PBX, Rift, taxi, remedy or security concepts;
- released game → studio frontend.

## Staged physical layout

The destination layout is `apps/studio`, narrow `crates/ums-*` capabilities,
`profiles`, `adapters`, `schemas`, `docs` and `tests/roundtrip`. This change
creates only one new crate because it already has real code and tests:
`ums-profile-sdk`.

The working engine and bridge remain in `ums-ai-edit` and `ums-dlc` while their
interfaces are separated. They are compatibility facades, not evidence that
the destination crate split is complete. Empty aspirational crates are
forbidden.

## Host-neutral model boundary

The universal layer may represent:

- stable identity, components, composition, state and events;
- space, time, agency, perception, knowledge, goals and relationships;
- affect and narrative relationships;
- asset and presentation references;
- constraints, tests, provenance, diffs and immutable edit history;
- package kinds and namespaced capabilities.

It may not define a game's nouns or doctrine. PBX, anti-hackers, keycards,
security tiers and IDApTIK alert doctrine belong to the IDApTIK profile. The
Rift, living taxis, remedies and Slavia's heroine influences belong to the
Chronicles of Slavia profile.

## Current executable path

```text
Nickel IDApTIK vocabulary + verbs
        -> generated Rust registry + generated profile reflection
        -> ums-ai-edit relational apply/solve
        -> IDApTIK constraints
        -> ums-dlc manifest and payload validation
        -> package fixture
```

The inputs are immutable and each successful edit produces a new state.
Finite-domain values may be solved; identifiers and geometry are refused when
the caller has not supplied them. Existing DLC remains valid.

The missing production round trip is:

```text
validated UMS model
    -> IDApTIK profile compiler
    -> package bytes
    -> real IDApTIK loader
    -> canonical game model
    -> exported/observed equivalence assertion
```

See `docs/ROUNDTRIP-STATUS.adoc`.

## Guarantee vocabulary

- **machine-checked**: accepted by the named type/proof checker;
- **runtime-validated**: evaluated by a runtime contract;
- **tested**: exercised by executable tests;
- **designed**: contract exists but is not implemented end to end;
- **aspirational**: intended future behavior without a completed contract.

miniKanren constraints are runtime relations. Idris2 typechecking is
machine-checked only for the modules and claims actually accepted by Idris2.
