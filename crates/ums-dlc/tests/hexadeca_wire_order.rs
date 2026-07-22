// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
//! The Hexadeca wire order agrees across Zig, Rust and Idris2.
//!
//! This is the test the whole connector layer exists for. A connector tag
//! crosses the FFI boundary as a `u8`. If the three languages disagree about
//! which number means which protocol, every call dispatches to the wrong
//! handler — **nothing crashes**, the wrong thing just happens, and the only
//! symptom is wrong behaviour far from the cause. It is the known failure
//! mode of this pattern across the estate.
//!
//! All three files are generated from `config/connectors.ncl`, so agreement
//! should hold by construction. This test proves it does, by reading the
//! generated Zig and Idris2 back and comparing them to the compiled Rust —
//! catching a broken generator, a hand-edit, or a stale committed artifact
//! that `gen-check` somehow let through.

use std::path::{Path, PathBuf};

use ums_dlc::hexadeca::{self, Connector};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("repo root")
}

fn read(rel: &str) -> String {
    std::fs::read_to_string(repo_root().join(rel)).unwrap_or_else(|e| panic!("{rel}: {e}"))
}

/// `    name = 7,` -> ("name", 7)
fn parse_zig_enum(src: &str) -> Vec<(String, u8)> {
    let body = src
        .split("pub const Connector = enum(u8) {")
        .nth(1)
        .expect("Zig enum block");
    let body = body.split("\n\n").next().expect("enum fields");
    body.lines()
        .filter_map(|l| {
            let l = l.trim().trim_end_matches(',');
            let (name, tag) = l.split_once(" = ")?;
            let tag: u8 = tag.trim().parse().ok()?;
            Some((name.trim().to_string(), tag))
        })
        .collect()
}

/// `connectorTag Grpc = 0` -> ("grpc", 0), via the name table.
fn parse_idris_tags(src: &str) -> Vec<(String, u8)> {
    let mut names: Vec<(String, String)> = Vec::new(); // (Pascal, wire name)
    for line in src.lines() {
        if let Some(rest) = line.strip_prefix("connectorName ")
            && let Some((ctor, quoted)) = rest.split_once(" = ")
        {
            names.push((
                ctor.trim().to_string(),
                quoted.trim().trim_matches('"').to_string(),
            ));
        }
    }
    let mut out = Vec::new();
    for line in src.lines() {
        if let Some(rest) = line.strip_prefix("connectorTag ")
            && let Some((ctor, tag)) = rest.split_once(" = ")
        {
            let ctor = ctor.trim();
            let tag: u8 = tag.trim().parse().expect("tag");
            let wire = names
                .iter()
                .find(|(c, _)| c == ctor)
                .map(|(_, w)| w.clone())
                .unwrap_or_else(|| panic!("no connectorName for {ctor}"));
            out.push((wire, tag));
        }
    }
    out
}

fn rust_pairs() -> Vec<(String, u8)> {
    hexadeca::ALL
        .iter()
        .map(|c| (c.name().to_string(), c.tag()))
        .collect()
}

#[test]
fn the_set_has_exactly_sixteen_members() {
    assert_eq!(hexadeca::CONNECTOR_COUNT, 16, "'Hexadeca' means sixteen");
    assert_eq!(hexadeca::ALL.len(), 16);
}

#[test]
fn zig_and_rust_agree_on_every_tag() {
    let zig = parse_zig_enum(&read("ffi/zig/src/hexadeca.zig"));
    assert_eq!(
        zig.len(),
        16,
        "parsed {} Zig fields, expected 16",
        zig.len()
    );
    assert_eq!(
        zig,
        rust_pairs(),
        "Zig and Rust disagree on the wire order; every FFI call would dispatch to the wrong handler"
    );
}

#[test]
fn idris_and_rust_agree_on_every_tag() {
    let idris = parse_idris_tags(&read("abi/Hexadeca.idr"));
    assert_eq!(idris.len(), 16, "parsed {} Idris2 tags", idris.len());
    assert_eq!(
        idris,
        rust_pairs(),
        "Idris2 and Rust disagree on the wire order"
    );
}

#[test]
fn tags_are_dense_from_zero() {
    // Density is what lets `from_tag` index directly and what makes an
    // out-of-range byte detectable rather than silently valid.
    for (i, c) in hexadeca::ALL.iter().enumerate() {
        assert_eq!(c.tag() as usize, i);
    }
}

#[test]
fn an_out_of_range_tag_is_rejected_not_coerced() {
    assert!(Connector::from_tag(16).is_none());
    assert!(Connector::from_tag(255).is_none());
    assert_eq!(Connector::from_tag(2), Some(Connector::Rest));
}

#[test]
fn the_implemented_count_is_honest() {
    // The reference implementation in paint-type ships sixteen stubs whose
    // dispatch returns 0. Here the count of real handlers is declared, and
    // must match what the connectors actually report.
    let counted = hexadeca::ALL.iter().filter(|c| c.is_implemented()).count();
    assert_eq!(
        counted,
        hexadeca::IMPLEMENTED_COUNT,
        "IMPLEMENTED_COUNT disagrees with the connectors themselves"
    );
    assert!(
        counted < 16,
        "if every connector is implemented, delete this assertion and say so"
    );
}

#[test]
fn names_are_distinct_and_snake_case() {
    let mut names: Vec<&str> = hexadeca::ALL.iter().map(|c| c.name()).collect();
    let before = names.len();
    names.sort_unstable();
    names.dedup();
    assert_eq!(before, names.len(), "duplicate connector name");
    for n in &names {
        assert!(
            n.chars()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_'),
            "{n} is not snake_case"
        );
    }
}
