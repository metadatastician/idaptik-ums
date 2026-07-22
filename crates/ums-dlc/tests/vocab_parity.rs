// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
//! The shared vocabularies agree across `config/vocab.ncl`, `abi/Types.idr`
//! and `ffi/zig/src/types.zig`.
//!
//! These are the last two hand-maintained copies of the closed worlds. The
//! Nickel source generates the JSON Schema and the Rust registry, but the
//! Idris2 ABI enums and the Zig FFI enums are still written by hand — so
//! nothing structurally prevents them drifting.
//!
//! **Order is the contract, not just membership.** `types.zig` declares
//! `enum(u8)` with explicit ordinals, and those bytes cross the FFI boundary.
//! A reordering that keeps the same members is invisible to a set comparison
//! and silently remaps every value — the same failure mode the Hexadeca
//! connector gate exists for, and the reason this test compares sequences.
//!
//! Scope: only the four vocabularies that genuinely overlap all three.
//! `AlertLevel` and `ItemCondition` are ABI-only; the UMS-owned edit
//! vocabularies (NPC roles, character archetypes/modifiers, item categories)
//! have no ABI enum. Asserting a correspondence that does not exist would be
//! worse than asserting none.

use std::path::{Path, PathBuf};

use serde_json::Value;
use ums_ai_edit::vocab;

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("repo root")
}

fn read(rel: &str) -> String {
    std::fs::read_to_string(repo_root().join(rel)).unwrap_or_else(|e| panic!("{rel}: {e}"))
}

/// PascalCase -> snake_case, matching the Zig field convention.
fn snake(s: &str) -> String {
    let mut out = String::new();
    for (i, c) in s.char_indices() {
        if c.is_ascii_uppercase() && i != 0 {
            out.push('_');
        }
        out.push(c.to_ascii_lowercase());
    }
    out
}

/// Constructors of `data <name>` in declaration order.
fn idris_constructors(src: &str, name: &str) -> Vec<String> {
    let start = src
        .find(&format!("data {name}"))
        .unwrap_or_else(|| panic!("no `data {name}` in abi/Types.idr"));
    let rest = &src[start..];
    // The declaration ends at the next blank line followed by a new item.
    let body = rest.split("\n\npublic export").next().unwrap_or(rest);
    let body = &body[body.find(name).map(|i| i + name.len()).unwrap_or(0)..];

    let mut out = Vec::new();
    for token in body.split(['=', '|']).skip(1) {
        let word: String = token
            .trim()
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric())
            .collect();
        if !word.is_empty() && word.chars().next().is_some_and(|c| c.is_ascii_uppercase()) {
            out.push(word);
        }
    }
    out
}

/// `field = N,` pairs of a `pub const <name> = enum(u8)`, in order.
fn zig_enum(src: &str, name: &str) -> Vec<(String, u8)> {
    let needle = format!("pub const {name} = enum(u8) {{");
    let start = src
        .find(&needle)
        .unwrap_or_else(|| panic!("no `{name}` enum in ffi/zig/src/types.zig"));
    let body = &src[start + needle.len()..];
    let body = body.split("\n};").next().expect("enum body");
    body.lines()
        .filter_map(|l| {
            let l = l.trim().trim_end_matches(',');
            let (f, t) = l.split_once(" = ")?;
            // `switch_` — the trailing underscore escapes a Zig keyword.
            Some((f.trim().trim_end_matches('_').to_string(), t.trim().parse().ok()?))
        })
        .collect()
}

/// The four vocabularies shared by all three languages.
fn shared() -> Vec<(&'static str, &'static [&'static str])> {
    vec![
        ("DeviceKind", &vocab::DEVICE_KINDS[..]),
        ("GuardRank", &vocab::GUARD_RANKS[..]),
        ("DogBreed", &vocab::DOG_BREEDS[..]),
        ("DroneArchetype", &vocab::DRONE_ARCHETYPES[..]),
    ]
}

#[test]
fn idris_abi_enums_match_the_nickel_source_in_order() {
    let src = read("abi/Types.idr");
    for (ty, want) in shared() {
        let got = idris_constructors(&src, ty);
        assert_eq!(
            got,
            want.to_vec(),
            "abi/Types.idr `data {ty}` has drifted from config/vocab.ncl"
        );
    }
}

#[test]
fn zig_ffi_enums_match_the_nickel_source_in_order() {
    let src = read("ffi/zig/src/types.zig");
    for (ty, want) in shared() {
        let got = zig_enum(&src, ty);
        let names: Vec<String> = got.iter().map(|(n, _)| n.clone()).collect();
        let expected: Vec<String> = want.iter().map(|w| snake(w)).collect();
        assert_eq!(
            names, expected,
            "ffi/zig/src/types.zig `{ty}` has drifted from config/vocab.ncl"
        );
    }
}

#[test]
fn zig_ffi_ordinals_are_dense_from_zero() {
    // The ordinal is what crosses the FFI boundary. A reordering that keeps
    // the same members is invisible to a membership check and silently
    // remaps every value.
    let src = read("ffi/zig/src/types.zig");
    for (ty, want) in shared() {
        let tags: Vec<u8> = zig_enum(&src, ty).iter().map(|(_, t)| *t).collect();
        let expected: Vec<u8> = (0..want.len() as u8).collect();
        assert_eq!(
            tags, expected,
            "ffi/zig/src/types.zig `{ty}` ordinals are not 0..{} in order",
            want.len()
        );
    }
}

#[test]
fn the_generated_schema_agrees_too() {
    // Closing the loop: the JSON Schema IS generated from vocab.ncl, so this
    // should hold by construction — but it costs nothing to pin, and it
    // catches a generator that silently stopped regenerating.
    let schema: Value = serde_json::from_str(&read("schemas/edit-script.schema.json")).unwrap();
    let kinds: Vec<&str> = schema["$defs"]["add_device"]["properties"]["kind"]["enum"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|v| v.as_str())
        .collect();
    assert_eq!(kinds, vocab::DEVICE_KINDS.to_vec());
}

#[test]
fn abi_only_vocabularies_are_deliberately_out_of_scope() {
    // AlertLevel and ItemCondition exist in the ABI and have no counterpart
    // in the edit vocabularies. Named here so that "why isn't this checked?"
    // has an answer in the test file rather than in someone's memory.
    let src = read("abi/Types.idr");
    for ty in ["AlertLevel", "ItemCondition"] {
        assert!(
            !idris_constructors(&src, ty).is_empty(),
            "{ty} was expected to exist in the ABI and be out of scope here"
        );
    }
}
