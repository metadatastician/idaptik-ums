// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
//! The UMS ↔ game bridge contract checker.
//!
//! Validates every DLC artifact against the contracts in `schemas/`: manifest
//! envelopes, puzzle payloads, vault sequences and edit scripts — including
//! the cross-field invariants JSON Schema cannot express (an edit script may
//! not reference a zone declared later; `optimalMoves <= maxMoves`;
//! `hasPBX` implies an IP and a position; the taxonomy map's tier bands must
//! start at 0 and strictly increase).
//!
//! Replaces `scripts/validate_dlc.py`, which hard-coded a *third* copy of the
//! closed vocabularies and a *second* copy of the verb registry. Both now come
//! from [`ums_ai_edit::vocab`], which `just gen` generates from
//! `config/vocab.ncl` and `config/verbs.ncl`. The validator and the engine
//! therefore cannot disagree about what a valid edit is — previously they
//! could, and only a hand-written test stood between them.

#![forbid(unsafe_code)]

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use serde_json::Value;
use ums_ai_edit::vocab;

pub mod taxonomy;

// ---------------------------------------------------------------------------
// Small predicates
// ---------------------------------------------------------------------------

/// Lowercase-kebab: `^[a-z0-9][a-z0-9-]*$`.
pub fn is_kebab(s: &str) -> bool {
    let mut chars = s.chars();
    match chars.next() {
        Some(c) if c.is_ascii_lowercase() || c.is_ascii_digit() => {}
        _ => return false,
    }
    s.chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

/// An identifier: `^[a-z][a-z0-9_]*$`.
pub fn is_ident(s: &str) -> bool {
    let mut chars = s.chars();
    match chars.next() {
        Some(c) if c.is_ascii_lowercase() => {}
        _ => return false,
    }
    s.chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
}

/// Semver `MAJOR.MINOR.PATCH` with optional `-pre` and `+build`.
pub fn is_semver(s: &str) -> bool {
    let core = s.split(['-', '+']).next().unwrap_or("");
    let parts: Vec<&str> = core.split('.').collect();
    parts.len() == 3
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.chars().all(|c| c.is_ascii_digit()))
}

/// `YYYY-MM-DD`.
pub fn is_iso_date(s: &str) -> bool {
    let p: Vec<&str> = s.split('-').collect();
    p.len() == 3
        && p[0].len() == 4
        && p[1].len() == 2
        && p[2].len() == 2
        && p.iter().all(|q| q.chars().all(|c| c.is_ascii_digit()))
}

/// A versioned profile payload tag such as `idaptik-edit/1`.
pub fn is_payload_format(s: &str) -> bool {
    let Some((name, n)) = s.split_once('/') else {
        return false;
    };
    is_kebab(name) && name.contains('-') && !n.is_empty() && n.chars().all(|c| c.is_ascii_digit())
}

/// A namespaced package capability such as `systems.network-topology`.
pub fn is_capability(s: &str) -> bool {
    s.split('.').count() >= 2 && s.split('.').all(is_kebab)
}

/// A JSON number that is not a bool.
fn is_number(v: Option<&Value>) -> bool {
    matches!(v, Some(Value::Number(_)))
}

/// A JSON integer >= `min` that is not a bool.
fn is_uint(v: Option<&Value>, min: i64) -> bool {
    v.and_then(|x| x.as_i64()).is_some_and(|i| i >= min)
}

fn keys(v: &Value) -> BTreeSet<String> {
    v.as_object()
        .map(|o| o.keys().cloned().collect())
        .unwrap_or_default()
}

fn set(items: &[&str]) -> BTreeSet<String> {
    items.iter().map(|s| (*s).to_string()).collect()
}

fn sorted(s: &BTreeSet<String>) -> Vec<String> {
    s.iter().cloned().collect()
}

/// A closed world, sorted, for an error message. Declaration order is right
/// for enumeration (solve() depends on it) but sorted order is easier to scan
/// when the list is twelve items long.
fn sorted_strs(items: &[&str]) -> Vec<String> {
    let mut v: Vec<String> = items.iter().map(|s| (*s).to_string()).collect();
    v.sort();
    v
}

// ---------------------------------------------------------------------------
// Closed worlds owned by the bridge (not by the edit vocabulary)
// ---------------------------------------------------------------------------

const MANIFEST_KINDS: [&str; 14] = [
    "scenario",
    "campaign",
    "content-pack",
    "ruleset",
    "generator",
    "presentation-pack",
    "compatibility-patch",
    "studio-extension",
    "edit-script",
    // v1 compatibility aliases. These remain valid until an explicit
    // package migration is selected by the author.
    "gameplay-mechanic",
    "puzzle-pack",
    "scenario-definition",
    "actor-pack",
    "asset-pack",
];
const COMPILE_TARGETS: [&str; 3] = ["wasmgc", "wasm32", "none"];
const MANIFEST_REQUIRED: [&str; 6] = ["id", "name", "version", "description", "license", "kind"];
const MANIFEST_EXTRA: [&str; 14] = [
    "$schema",
    "manifest-version",
    "profile",
    "author",
    "loads",
    "exports",
    "depends-on",
    "compile-target",
    "wasm-modules",
    "payload",
    "guarantees",
    "verification",
    "provides",
    "patches",
];

/// The reversible VM's instruction set (`dlc/vm/src/instructions/`).
const INSTRUCTIONS: [&str; 23] = [
    "ADD", "AND", "CALL", "DIV", "FLIP", "IFPOS", "IFZERO", "LOAD", "LOOP", "MUL", "NEGATE",
    "NOOP", "OR", "POP", "PUSH", "RECV", "ROL", "ROR", "SEND", "STORE", "SUB", "SWAP", "XOR",
];
const DIFFICULTIES: [&str; 4] = ["beginner", "intermediate", "advanced", "expert"];
const PUZZLE_REQUIRED: [&str; 10] = [
    "name",
    "description",
    "difficulty",
    "initialState",
    "goalState",
    "maxMoves",
    "optimalMoves",
    "allowedInstructions",
    "hints",
    "metadata",
];
const METADATA_ALLOWED: [&str; 5] = ["author", "created", "tags", "license", "version"];
const VAULT_REQUIRED: [&str; 4] = ["name", "description", "state", "steps"];
const VAULT_OPS: [&str; 3] = ["flip", "xor", "swap"];
const EDIT_SCRIPT_REQUIRED: [&str; 2] = ["target", "edits"];
const EDIT_SCRIPT_EXTRA: [&str; 2] = ["$schema", "format-note"];

// ---------------------------------------------------------------------------
// Register states
// ---------------------------------------------------------------------------

/// A register/bit state: identifiers mapped to integers (or to 0/1 only).
pub fn is_register_state(value: Option<&Value>, bits_only: bool) -> bool {
    let Some(Value::Object(map)) = value else {
        return false;
    };
    if map.is_empty() {
        return false;
    }
    map.iter().all(|(k, v)| {
        is_ident(k)
            && match v {
                Value::Number(n) => {
                    let Some(i) = n.as_i64() else { return false };
                    !bits_only || i == 0 || i == 1
                }
                _ => false,
            }
    })
}

// ---------------------------------------------------------------------------
// Manifests
// ---------------------------------------------------------------------------

pub fn check_manifest(doc: &Value, errors: &mut Vec<String>) {
    let present = keys(doc);
    let required = set(&MANIFEST_REQUIRED);
    let allowed: BTreeSet<String> = required.union(&set(&MANIFEST_EXTRA)).cloned().collect();

    let missing: BTreeSet<String> = required.difference(&present).cloned().collect();
    if !missing.is_empty() {
        errors.push(format!(
            "manifest missing required fields: {:?}",
            sorted(&missing)
        ));
    }
    let unknown: BTreeSet<String> = present.difference(&allowed).cloned().collect();
    if !unknown.is_empty() {
        errors.push(format!(
            "manifest has unknown fields: {:?}",
            sorted(&unknown)
        ));
    }

    if let Some(id) = doc.get("id")
        && !id.as_str().is_some_and(is_kebab)
    {
        errors.push("id must be lowercase-kebab".into());
    }
    if let Some(v) = doc.get("version")
        && !v.as_str().is_some_and(is_semver)
    {
        errors.push("version must be semver".into());
    }
    if let Some(v) = doc.get("manifest-version")
        && v.as_u64().is_none_or(|version| version != 2)
    {
        errors.push("manifest-version must be 2 when present".into());
    }
    if let Some(profile) = doc.get("profile")
        && !profile.as_str().is_some_and(ums_profile_sdk::is_profile_id)
    {
        errors.push("profile must be a lowercase dotted-kebab profile ID".into());
    }
    for field in ["name", "description", "license"] {
        if let Some(v) = doc.get(field)
            && v.as_str().is_none_or(|s| s.is_empty())
        {
            errors.push(format!("{field} must be a non-empty string"));
        }
    }
    if let Some(k) = doc.get("kind")
        && !k.as_str().is_some_and(|s| MANIFEST_KINDS.contains(&s))
    {
        errors.push(format!(
            "kind must be one of {:?}",
            sorted_strs(&MANIFEST_KINDS)
        ));
    }
    if let Some(t) = doc.get("compile-target")
        && !t.as_str().is_some_and(|s| COMPILE_TARGETS.contains(&s))
    {
        errors.push(format!(
            "compile-target must be one of {:?}",
            sorted_strs(&COMPILE_TARGETS)
        ));
    }
    for field in ["exports", "depends-on", "verification"] {
        if let Some(v) = doc.get(field)
            && !v
                .as_object()
                .is_some_and(|o| o.values().all(|x| x.is_string()))
        {
            errors.push(format!("{field} must map names to strings"));
        }
    }
    for field in ["wasm-modules", "guarantees"] {
        if let Some(v) = doc.get(field)
            && !v
                .as_array()
                .is_some_and(|a| a.iter().all(|x| x.is_string()))
        {
            errors.push(format!("{field} must be an array of strings"));
        }
    }
    for field in ["provides", "patches"] {
        if let Some(v) = doc.get(field)
            && !v.as_array().is_some_and(|items| {
                items
                    .iter()
                    .all(|item| item.as_str().is_some_and(is_capability))
            })
        {
            errors.push(format!(
                "{field} must be an array of namespaced capabilities"
            ));
        }
    }

    let kind = doc.get("kind").and_then(|k| k.as_str());
    match doc.get("payload") {
        None => {
            if kind == Some("edit-script") {
                errors.push("kind edit-script requires a payload block".into());
            }
        }
        Some(payload) => {
            let Some(obj) = payload.as_object() else {
                errors.push("payload must be an object".into());
                return;
            };
            if keys(payload) != set(&["format", "path"]) {
                errors.push("payload must have exactly format and path".into());
            }
            let fmt = obj.get("format").and_then(|f| f.as_str());
            if !fmt.is_some_and(is_payload_format) {
                errors.push("payload.format must match idaptik-<type>/<n>".into());
            }
            if obj
                .get("path")
                .and_then(|p| p.as_str())
                .is_none_or(|s| s.is_empty())
            {
                errors.push("payload.path must be a non-empty string".into());
            }
            if let Some(f) = fmt {
                let is_edit = f.starts_with("idaptik-edit/");
                if kind == Some("edit-script") && !is_edit {
                    errors.push("kind edit-script requires payload.format idaptik-edit/<n>".into());
                }
                if is_edit && kind != Some("edit-script") {
                    errors.push("payload.format idaptik-edit/<n> requires kind edit-script".into());
                }
            }
        }
    }
}

/// Upgrade a valid v1 manifest to the capability-aware v2 envelope.
///
/// Migration is opt-in and non-destructive: [`check_manifest`] continues to
/// accept every shipped v1 kind. The mapping deliberately stays broad; it
/// does not manufacture capabilities that the old manifest never declared.
pub fn migrate_manifest_v1(doc: &Value) -> Result<Value, String> {
    let mut errors = Vec::new();
    check_manifest(doc, &mut errors);
    if !errors.is_empty() {
        return Err(errors.join("; "));
    }
    let mut migrated = doc.clone();
    let object = migrated
        .as_object_mut()
        .ok_or_else(|| "manifest must be an object".to_string())?;
    let new_kind = match object.get("kind").and_then(Value::as_str) {
        Some("gameplay-mechanic") => "ruleset",
        Some("puzzle-pack" | "actor-pack") => "content-pack",
        Some("scenario-definition") => "scenario",
        Some("asset-pack") => "presentation-pack",
        Some(kind) => kind,
        None => return Err("manifest has no kind".into()),
    };
    object.insert("kind".into(), Value::String(new_kind.into()));
    object.insert("manifest-version".into(), Value::from(2));
    object
        .entry("provides")
        .or_insert_with(|| Value::Array(Vec::new()));
    object
        .entry("patches")
        .or_insert_with(|| Value::Array(Vec::new()));
    Ok(migrated)
}

// ---------------------------------------------------------------------------
// Register puzzles
// ---------------------------------------------------------------------------

pub fn check_register_puzzle(doc: &Value, errors: &mut Vec<String>) {
    let present = keys(doc);
    let required = set(&PUZZLE_REQUIRED);
    let missing: BTreeSet<String> = required.difference(&present).cloned().collect();
    if !missing.is_empty() {
        errors.push(format!(
            "puzzle missing required fields: {:?}",
            sorted(&missing)
        ));
    }
    let unknown: BTreeSet<String> = present.difference(&required).cloned().collect();
    if !unknown.is_empty() {
        errors.push(format!("puzzle has unknown fields: {:?}", sorted(&unknown)));
    }

    if let Some(d) = doc.get("difficulty")
        && !d.as_str().is_some_and(|s| DIFFICULTIES.contains(&s))
    {
        errors.push(format!(
            "difficulty must be one of {:?}",
            sorted_strs(&DIFFICULTIES)
        ));
    }
    for field in ["initialState", "goalState"] {
        if doc.get(field).is_some() && !is_register_state(doc.get(field), false) {
            errors.push(format!("{field} must map identifiers to integers"));
        }
    }
    if let (Some(Value::Object(i)), Some(Value::Object(g))) =
        (doc.get("initialState"), doc.get("goalState"))
    {
        let (ik, gk): (Vec<&String>, Vec<&String>) = (i.keys().collect(), g.keys().collect());
        if ik != gk {
            errors.push(format!(
                "initialState and goalState must share one register set ({ik:?} vs {gk:?})"
            ));
        }
    }
    for field in ["maxMoves", "optimalMoves"] {
        if doc.get(field).is_some() && !is_uint(doc.get(field), 1) {
            errors.push(format!("{field} must be an integer >= 1"));
        }
    }
    if let (Some(max), Some(opt)) = (
        doc.get("maxMoves").and_then(|v| v.as_i64()),
        doc.get("optimalMoves").and_then(|v| v.as_i64()),
    ) && opt > max
    {
        errors.push("optimalMoves must be <= maxMoves".into());
    }

    if let Some(instructions) = doc.get("allowedInstructions") {
        match instructions.as_array() {
            Some(a) if !a.is_empty() => {
                let bogus: Vec<&str> = a
                    .iter()
                    .filter_map(|i| i.as_str())
                    .filter(|i| !INSTRUCTIONS.contains(i))
                    .collect();
                if !bogus.is_empty() {
                    errors.push(format!("unknown instructions: {bogus:?}"));
                }
                let distinct: BTreeSet<&str> = a.iter().filter_map(|i| i.as_str()).collect();
                if distinct.len() != a.len() {
                    errors.push("allowedInstructions must not repeat".into());
                }
            }
            _ => errors.push("allowedInstructions must be a non-empty array".into()),
        }
    }

    if let Some(hints) = doc.get("hints") {
        match hints.as_array() {
            None => errors.push("hints must be an array".into()),
            Some(a) => {
                for (i, hint) in a.iter().enumerate() {
                    let ok = keys(hint) == set(&["moveNumber", "text"])
                        && is_uint(hint.get("moveNumber"), 0)
                        && hint
                            .get("text")
                            .and_then(|t| t.as_str())
                            .is_some_and(|s| !s.is_empty());
                    if !ok {
                        errors.push(format!("hints[{i}] must be {{moveNumber >= 0, text}}"));
                    }
                }
            }
        }
    }

    if let Some(metadata) = doc.get("metadata") {
        if metadata.as_object().is_none() {
            errors.push("metadata must be an object".into());
        } else {
            let present = keys(metadata);
            if !set(&["author", "created", "tags"]).is_subset(&present) {
                errors.push("metadata requires author, created, tags".into());
            }
            let unknown: BTreeSet<String> = present
                .difference(&set(&METADATA_ALLOWED))
                .cloned()
                .collect();
            if !unknown.is_empty() {
                errors.push(format!(
                    "metadata has unknown fields: {:?}",
                    sorted(&unknown)
                ));
            }
            if let Some(c) = metadata.get("created")
                && !c.as_str().is_some_and(is_iso_date)
            {
                errors.push("metadata.created must be YYYY-MM-DD".into());
            }
            if let Some(t) = metadata.get("tags")
                && !t
                    .as_array()
                    .is_some_and(|a| a.iter().all(|x| x.is_string()))
            {
                errors.push("metadata.tags must be an array of strings".into());
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Vault sequences
// ---------------------------------------------------------------------------

pub fn check_vault_sequence(doc: &Value, errors: &mut Vec<String>) {
    let present = keys(doc);
    let required = set(&VAULT_REQUIRED);
    let missing: BTreeSet<String> = required.difference(&present).cloned().collect();
    if !missing.is_empty() {
        errors.push(format!(
            "vault missing required fields: {:?}",
            sorted(&missing)
        ));
    }
    let unknown: BTreeSet<String> = present.difference(&required).cloned().collect();
    if !unknown.is_empty() {
        errors.push(format!("vault has unknown fields: {:?}", sorted(&unknown)));
    }

    if doc.get("state").is_some() && !is_register_state(doc.get("state"), true) {
        errors.push("state must map identifiers to bits (0/1)".into());
    }
    let bits: BTreeSet<String> = doc
        .get("state")
        .and_then(|s| s.as_object())
        .map(|o| o.keys().cloned().collect())
        .unwrap_or_default();

    let Some(steps) = doc.get("steps") else {
        return;
    };
    let Some(steps) = steps.as_array().filter(|a| !a.is_empty()) else {
        errors.push("steps must be a non-empty array".into());
        return;
    };

    for (i, step) in steps.iter().enumerate() {
        let op = step.get("op").and_then(|o| o.as_str());
        let Some(op) = op.filter(|o| VAULT_OPS.contains(o)) else {
            errors.push(format!(
                "steps[{i}].op must be one of {:?}",
                sorted_strs(&VAULT_OPS)
            ));
            continue;
        };
        let k = keys(step);
        let mut named: Vec<String> = Vec::new();

        match op {
            "flip" => {
                if k != set(&["op", "target"]) || !step.get("target").is_some_and(|t| t.is_string())
                {
                    errors.push(format!("steps[{i}]: flip takes exactly a target bit"));
                }
                if let Some(t) = step.get("target").and_then(|t| t.as_str()) {
                    named.push(t.into());
                }
            }
            "swap" => {
                if k != set(&["op", "targets"]) {
                    errors.push(format!("steps[{i}]: swap takes exactly two targets"));
                }
                if let Some(a) = step.get("targets").and_then(|t| t.as_array()) {
                    named.extend(a.iter().filter_map(|t| t.as_str().map(String::from)));
                }
            }
            "xor" => {
                if k != set(&["op", "targets"]) && k != set(&["op", "targets", "result"]) {
                    errors.push(format!(
                        "steps[{i}]: xor takes two targets and an optional result"
                    ));
                }
                if let Some(a) = step.get("targets").and_then(|t| t.as_array()) {
                    named.extend(a.iter().filter_map(|t| t.as_str().map(String::from)));
                }
                if let Some(r) = step.get("result").and_then(|r| r.as_str()) {
                    named.push(r.into());
                }
            }
            _ => unreachable!("op was filtered against VAULT_OPS"),
        }

        if let Some(t) = step.get("targets") {
            let ok = t
                .as_array()
                .is_some_and(|a| a.len() == 2 && a.iter().all(|x| x.is_string()));
            if !ok {
                errors.push(format!("steps[{i}].targets must be exactly two bit names"));
            }
        }
        for bit in named {
            if !bits.is_empty() && !bits.contains(&bit) {
                errors.push(format!("steps[{i}] references unknown bit '{bit}'"));
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Edit scripts
// ---------------------------------------------------------------------------

/// Validate an `idaptik-edit/1` payload.
///
/// The verb surface, the required/optional argument split and every closed
/// vocabulary come from [`ums_ai_edit::vocab`] — generated from
/// `config/verbs.ncl`. The Python this replaces re-declared all of it, so the
/// validator and the engine could disagree about what a valid edit was.
pub fn check_edit_script(doc: &Value, errors: &mut Vec<String>) {
    let present = keys(doc);
    let required = set(&EDIT_SCRIPT_REQUIRED);
    let allowed: BTreeSet<String> = required.union(&set(&EDIT_SCRIPT_EXTRA)).cloned().collect();

    let missing: BTreeSet<String> = required.difference(&present).cloned().collect();
    if !missing.is_empty() {
        errors.push(format!(
            "edit script missing required fields: {:?}",
            sorted(&missing)
        ));
    }
    let unknown: BTreeSet<String> = present.difference(&allowed).cloned().collect();
    if !unknown.is_empty() {
        errors.push(format!(
            "edit script has unknown fields: {:?}",
            sorted(&unknown)
        ));
    }
    if let Some(t) = doc.get("target")
        && !t.as_str().is_some_and(is_kebab)
    {
        errors.push("target must be lowercase-kebab".into());
    }

    let Some(edits) = doc.get("edits") else {
        return;
    };
    let Some(edits) = edits.as_array().filter(|a| !a.is_empty()) else {
        errors.push("edits must be a non-empty array".into());
        return;
    };

    // Where each zone is declared, so a later verb cannot reference a zone
    // declared after it. Zones the script never declares are assumed to
    // pre-exist on the target scenario; the engine re-checks against the real
    // level.
    let mut declared_zones: BTreeMap<String, usize> = BTreeMap::new();
    let mut declared_entities: BTreeSet<String> = BTreeSet::new();

    for (i, edit) in edits.iter().enumerate() {
        let verb_name = edit.get("verb").and_then(|v| v.as_str()).unwrap_or("");
        let Some(spec) = vocab::verb(verb_name) else {
            let mut names: Vec<&str> = vocab::VERBS.iter().map(|v| v.name).collect();
            names.sort_unstable();
            errors.push(format!("edits[{i}].verb must be one of {names:?}"));
            continue;
        };

        let expected: BTreeSet<String> = spec
            .required
            .iter()
            .map(|s| (*s).to_string())
            .chain(std::iter::once("verb".to_string()))
            .collect();
        let optional: BTreeSet<String> = spec
            .args
            .iter()
            .filter(|a| !spec.required.contains(*a))
            .map(|s| (*s).to_string())
            .collect();
        let k = keys(edit);
        let extra: BTreeSet<String> = k.difference(&expected).cloned().collect();
        let surplus: BTreeSet<String> = extra.difference(&optional).cloned().collect();
        if !expected.is_subset(&k) || !surplus.is_empty() {
            let mut want: Vec<String> = expected.iter().cloned().collect();
            want.retain(|s| s != "verb");
            let suffix = if optional.is_empty() {
                String::new()
            } else {
                format!(" (plus optional {:?})", sorted(&optional))
            };
            errors.push(format!(
                "edits[{i}]: {verb_name} takes exactly {want:?}{suffix}"
            ));
            continue;
        }

        if let Some(id) = edit.get("id")
            && !id.as_str().is_some_and(is_kebab)
        {
            errors.push(format!("edits[{i}].id must be lowercase-kebab"));
        }

        // Every closed-world argument, straight from the generated registry.
        for (field, domain) in spec.domains.iter() {
            if let Some(v) = edit.get(*field) {
                let ok = v.as_str().is_some_and(|s| domain.contains(&s));
                if !ok {
                    errors.push(format!(
                        "edits[{i}].{field} must be one of {:?}",
                        sorted_strs(domain)
                    ));
                }
            }
        }

        match verb_name {
            "add_zone" => {
                for field in ["worldXStart", "worldXEnd"] {
                    if !is_number(edit.get(field)) {
                        errors.push(format!("edits[{i}].{field} must be a number"));
                    }
                }
                if !is_uint(edit.get("securityTier"), 0) {
                    errors.push(format!("edits[{i}].securityTier must be an integer >= 0"));
                }
                if let Some(zone_id) = edit.get("id").and_then(|v| v.as_str()) {
                    if declared_zones.contains_key(zone_id) {
                        errors.push(format!("edits[{i}] redeclares zone '{zone_id}'"));
                    } else {
                        declared_zones.insert(zone_id.into(), i);
                    }
                }
            }
            "add_device" if !is_number(edit.get("worldX")) => {
                errors.push(format!("edits[{i}].worldX must be a number"));
            }
            "set_mission" | "set_physical" => {
                let field = &verb_name[4..];
                match edit.get(field).and_then(|b| b.as_object()) {
                    None => errors.push(format!("edits[{i}].{field} must be an object")),
                    Some(block) => {
                        if verb_name == "set_physical"
                            && block.get("hasPBX").is_some_and(|v| v == &Value::Bool(true))
                        {
                            let ip_ok = block
                                .get("pbxIp")
                                .and_then(|v| v.as_str())
                                .is_some_and(|s| !s.is_empty());
                            if !ip_ok || !is_number(block.get("pbxWorldX")) {
                                errors.push(format!(
                                    "edits[{i}]: hasPBX requires pbxIp (string) and pbxWorldX (number)"
                                ));
                            }
                        }
                    }
                }
            }
            _ => {}
        }

        if verb_name != "add_zone"
            && let Some(entity_id) = edit.get("id").and_then(|v| v.as_str())
            && !declared_entities.insert(entity_id.to_string())
        {
            errors.push(format!("edits[{i}] reuses entity id '{entity_id}'"));
        }

        // Forward reference: a zone declared later in the same script.
        if let Some(zone_ref) = edit.get("zone").and_then(|v| v.as_str())
            && let Some(declared_at) = edits.iter().position(|e| {
                e.get("verb").and_then(|v| v.as_str()) == Some("add_zone")
                    && e.get("id").and_then(|v| v.as_str()) == Some(zone_ref)
            })
            && declared_at > i
        {
            errors.push(format!(
                "edits[{i}] references zone '{zone_ref}' declared later (edits[{declared_at}])"
            ));
        }
    }
}

// ---------------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------------

/// Route a document to its contract by filename and shape, exactly as the
/// Python did: manifests by name, then edit scripts, then vault sequences,
/// then register puzzles.
pub fn classify_and_check(path: &Path, doc: &Value, errors: &mut Vec<String>) {
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
    if name == "dlc-manifest.json" {
        check_manifest(doc, errors);
    } else if doc.get("edits").is_some() {
        check_edit_script(doc, errors);
    } else if doc.get("steps").is_some() || doc.get("state").is_some() {
        check_vault_sequence(doc, errors);
    } else {
        check_register_puzzle(doc, errors);
    }
}
