// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
//! The DLC bridge contract, pinned.
//!
//! Ported from `tests/test_taxonomy_map.py` and from the differential harness
//! that compared this validator against the Python it replaces. The mutation
//! cases below are the interesting half: a validator is only worth anything
//! if it *rejects*, and every one of these was verified to produce the same
//! verdict and the same message as the Python before that file was deleted.

use std::path::{Path, PathBuf};

use serde_json::{Value, json};
use ums_ai_edit::vocab;
use ums_dlc::{
    check_edit_script, check_manifest, check_register_puzzle, check_vault_sequence,
    classify_and_check, taxonomy,
};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("repo root")
}

fn load(rel: &str) -> Value {
    let text = std::fs::read_to_string(repo_root().join(rel)).expect(rel);
    serde_json::from_str(&text).expect(rel)
}

fn taxonomy_map() -> Value {
    load("schemas/taxonomy-map.json")
}

/// Errors from validating an edit-script payload.
fn edit_errors(doc: &Value) -> Vec<String> {
    let mut e = Vec::new();
    check_edit_script(doc, &mut e);
    e
}

fn script_with(edits: Value) -> Value {
    json!({ "target": "exchange-house", "edits": edits })
}

// ---------------------------------------------------------------------------
// The taxonomy map (ported from tests/test_taxonomy_map.py)
// ---------------------------------------------------------------------------

#[test]
fn map_is_internally_coherent() {
    assert_eq!(taxonomy::check(&taxonomy_map()), Vec::<String>::new());
}

#[test]
fn device_kinds_cover_the_ums_vocabulary_exactly() {
    let map = taxonomy_map();
    let mapped: Vec<&str> = map["device-kinds"]
        .as_object()
        .unwrap()
        .keys()
        .map(|s| s.as_str())
        .collect();
    let mut mapped_sorted = mapped.clone();
    mapped_sorted.sort_unstable();
    let mut vocab_sorted = vocab::DEVICE_KINDS.to_vec();
    vocab_sorted.sort_unstable();
    assert_eq!(
        mapped_sorted, vocab_sorted,
        "the taxonomy map and the generated vocabulary disagree about DeviceKind"
    );
}

#[test]
fn device_mapping_is_lossless_one_to_one() {
    let map = taxonomy_map();
    let obj = map["device-kinds"].as_object().unwrap();
    let mut targets: Vec<&str> = obj.values().filter_map(|v| v.as_str()).collect();
    let before = targets.len();
    targets.sort_unstable();
    targets.dedup();
    assert_eq!(before, targets.len(), "two UMS kinds share a game kind");
}

#[test]
fn extend_the_enum_ruling_is_reflected_in_the_game_enum() {
    // ADR-0002: the game enum was extended to a SUPERSET of the UMS enum, so
    // every mapped target must exist game-side.
    let map = taxonomy_map();
    let game: Vec<&str> = map["game-device-kinds"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|v| v.as_str())
        .collect();
    for target in map["device-kinds"].as_object().unwrap().values() {
        let t = target.as_str().unwrap();
        assert!(game.contains(&t), "game enum is missing {t}");
    }
}

#[test]
fn edit_schema_device_enum_matches_the_map() {
    let schema = load("schemas/edit-script.schema.json");
    let enum_: Vec<&str> = schema["$defs"]["add_device"]["properties"]["kind"]["enum"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|v| v.as_str())
        .collect();
    let map = taxonomy_map();
    let mut mapped: Vec<&str> = map["device-kinds"]
        .as_object()
        .unwrap()
        .keys()
        .map(|s| s.as_str())
        .collect();
    let mut e = enum_.clone();
    e.sort_unstable();
    mapped.sort_unstable();
    assert_eq!(e, mapped);
}

#[test]
fn edit_schema_segment_enum_matches_the_map() {
    let schema = load("schemas/edit-script.schema.json");
    let enum_: Vec<&str> = schema["$defs"]["add_zone"]["properties"]["segment"]["enum"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|v| v.as_str())
        .collect();
    let map = taxonomy_map();
    let segments: Vec<&str> = map["zone-segments"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|v| v.as_str())
        .collect();
    assert_eq!(enum_, segments);
}

#[test]
fn validator_vocabularies_are_derived_from_the_map() {
    // The zone-segment domain the validator enforces IS the map's, because
    // both now come from config/vocab.ncl.
    let map = taxonomy_map();
    let segments: Vec<&str> = map["zone-segments"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|v| v.as_str())
        .collect();
    assert_eq!(segments, vocab::ZONE_SEGMENTS.to_vec());
}

#[test]
fn default_bands_resolve_every_tier() {
    // "Highest min-tier <= tier wins" is only unambiguous if the ladder
    // starts at 0 and strictly increases.
    let map = taxonomy_map();
    let bands = map["zone-tier-bands"].as_array().unwrap();
    assert_eq!(bands[0]["min-tier"], json!(0));
    let mut last = -1i64;
    for band in bands {
        let t = band["min-tier"].as_i64().unwrap();
        assert!(t > last, "min-tiers must strictly increase");
        last = t;
    }
}

// --- taxonomy map: the map must REJECT ------------------------------------

#[test]
fn taxonomy_rejects_a_band_ladder_that_does_not_start_at_zero() {
    let mut map = taxonomy_map();
    map["zone-tier-bands"][0] = json!({"min-tier": 1, "segment": "Lan"});
    let errors = taxonomy::check(&map);
    assert!(
        errors.iter().any(|e| e.contains("start at min-tier 0")),
        "{errors:?}"
    );
}

#[test]
fn taxonomy_rejects_non_increasing_bands() {
    let mut map = taxonomy_map();
    map["zone-tier-bands"][1]["min-tier"] = json!(0);
    let errors = taxonomy::check(&map);
    assert!(
        errors.iter().any(|e| e.contains("strictly increasing")),
        "{errors:?}"
    );
}

#[test]
fn taxonomy_rejects_a_target_missing_from_the_game_enum() {
    let mut map = taxonomy_map();
    map["device-kinds"]["Laptop"] = json!("NoSuchKind");
    let errors = taxonomy::check(&map);
    assert!(
        errors
            .iter()
            .any(|e| e.contains("not in game-device-kinds")),
        "{errors:?}"
    );
}

#[test]
fn taxonomy_rejects_a_non_one_to_one_map() {
    let mut map = taxonomy_map();
    map["device-kinds"]["Laptop"] = json!("Server");
    let errors = taxonomy::check(&map);
    assert!(errors.iter().any(|e| e.contains("1:1")), "{errors:?}");
}

#[test]
fn taxonomy_rejects_a_bad_format_string() {
    let mut map = taxonomy_map();
    map["format"] = json!("wrong/1");
    let errors = taxonomy::check(&map);
    assert!(
        errors.iter().any(|e| e.contains("idaptik-taxonomy-map")),
        "{errors:?}"
    );
}

// ---------------------------------------------------------------------------
// Edit scripts: the shipped artifact, and every way to break it
// ---------------------------------------------------------------------------

#[test]
fn the_shipped_sample_edit_script_is_valid() {
    let doc = load("dlc/examples/ai-edit-sample/edit-script.json");
    assert_eq!(edit_errors(&doc), Vec::<String>::new());
}

#[test]
fn add_zone_without_a_segment_override_is_valid() {
    let doc = script_with(
        json!([{"verb":"add_zone","id":"lobby","securityTier":0,"worldXStart":0,"worldXEnd":40}]),
    );
    assert_eq!(edit_errors(&doc), Vec::<String>::new());
}

#[test]
fn add_zone_with_a_valid_segment_override_is_valid() {
    let doc = script_with(json!([{"verb":"add_zone","id":"sr","securityTier":2,
                                  "worldXStart":0,"worldXEnd":9,"segment":"Internal"}]));
    assert_eq!(edit_errors(&doc), Vec::<String>::new());
}

#[test]
fn add_zone_with_an_unknown_segment_is_rejected() {
    let doc = script_with(json!([{"verb":"add_zone","id":"sr","securityTier":2,
                                  "worldXStart":0,"worldXEnd":9,"segment":"Nowhere"}]));
    let e = edit_errors(&doc);
    assert!(
        e.iter().any(|x| x.contains("segment must be one of")),
        "{e:?}"
    );
}

#[test]
fn add_zone_with_an_unknown_field_is_still_rejected() {
    // The optional-argument allowance must not become a hole through which
    // arbitrary fields pass.
    let doc = script_with(json!([{"verb":"add_zone","id":"sr","securityTier":2,
                                  "worldXStart":0,"worldXEnd":9,"nonsense":true}]));
    let e = edit_errors(&doc);
    assert!(e.iter().any(|x| x.contains("takes exactly")), "{e:?}");
}

#[test]
fn an_unknown_verb_is_rejected() {
    let doc = script_with(json!([{"verb":"summon_dragon"}]));
    let e = edit_errors(&doc);
    assert!(e.iter().any(|x| x.contains("verb must be one of")), "{e:?}");
}

#[test]
fn an_out_of_vocabulary_rank_is_rejected() {
    let doc = script_with(json!([
        {"verb":"add_zone","id":"lobby","securityTier":0,"worldXStart":0,"worldXEnd":40},
        {"verb":"add_guard","id":"g","rank":"Wizard","zone":"lobby"}
    ]));
    let e = edit_errors(&doc);
    assert!(e.iter().any(|x| x.contains("rank must be one of")), "{e:?}");
}

#[test]
fn a_forward_zone_reference_is_rejected() {
    // A zone declared LATER in the same script cannot be referenced earlier.
    let doc = script_with(json!([
        {"verb":"add_guard","id":"early","rank":"Sentinel","zone":"server-room"},
        {"verb":"add_zone","id":"server-room","securityTier":2,"worldXStart":0,"worldXEnd":9}
    ]));
    let e = edit_errors(&doc);
    assert!(e.iter().any(|x| x.contains("declared later")), "{e:?}");
}

#[test]
fn an_undeclared_zone_is_allowed_because_it_may_pre_exist() {
    // Zones the script never declares are assumed to exist on the target
    // scenario; the engine re-checks against the real level.
    let doc =
        script_with(json!([{"verb":"add_guard","id":"g","rank":"Sentinel","zone":"elsewhere"}]));
    assert_eq!(edit_errors(&doc), Vec::<String>::new());
}

#[test]
fn a_redeclared_zone_is_rejected() {
    let z = json!({"verb":"add_zone","id":"lobby","securityTier":0,"worldXStart":0,"worldXEnd":40});
    let doc = script_with(json!([z, z]));
    let e = edit_errors(&doc);
    assert!(e.iter().any(|x| x.contains("redeclares zone")), "{e:?}");
}

#[test]
fn a_reused_entity_id_is_rejected() {
    let doc = script_with(json!([
        {"verb":"add_zone","id":"lobby","securityTier":0,"worldXStart":0,"worldXEnd":40},
        {"verb":"add_item","id":"dup","category":"Tool","zone":"lobby"},
        {"verb":"add_item","id":"dup","category":"Loot","zone":"lobby"}
    ]));
    let e = edit_errors(&doc);
    assert!(e.iter().any(|x| x.contains("reuses entity id")), "{e:?}");
}

#[test]
fn a_missing_or_surplus_argument_is_rejected() {
    for edits in [
        json!([{"verb":"add_guard","id":"g","zone":"z"}]),
        json!([{"verb":"add_guard","id":"g","rank":"Sentinel","zone":"z","extra":1}]),
    ] {
        let e = edit_errors(&script_with(edits));
        assert!(e.iter().any(|x| x.contains("takes exactly")), "{e:?}");
    }
}

#[test]
fn non_numeric_geometry_is_rejected() {
    let doc = script_with(json!([
        {"verb":"add_zone","id":"z","securityTier":0,"worldXStart":"near","worldXEnd":40}
    ]));
    let e = edit_errors(&doc);
    assert!(
        e.iter().any(|x| x.contains("worldXStart must be a number")),
        "{e:?}"
    );
}

#[test]
fn a_negative_security_tier_is_rejected() {
    let doc = script_with(json!([
        {"verb":"add_zone","id":"z","securityTier":-1,"worldXStart":0,"worldXEnd":40}
    ]));
    let e = edit_errors(&doc);
    assert!(
        e.iter()
            .any(|x| x.contains("securityTier must be an integer >= 0")),
        "{e:?}"
    );
}

#[test]
fn haspbx_without_an_ip_or_position_is_rejected() {
    let doc = script_with(json!([{"verb":"set_physical","physical":{"hasPBX":true}}]));
    let e = edit_errors(&doc);
    assert!(e.iter().any(|x| x.contains("hasPBX requires")), "{e:?}");
}

#[test]
fn a_non_kebab_target_is_rejected() {
    let doc = json!({"target":"Not Kebab","edits":[
        {"verb":"add_zone","id":"z","securityTier":0,"worldXStart":0,"worldXEnd":1}]});
    let e = edit_errors(&doc);
    assert!(
        e.iter()
            .any(|x| x.contains("target must be lowercase-kebab")),
        "{e:?}"
    );
}

#[test]
fn an_empty_edit_list_is_rejected() {
    let e = edit_errors(&script_with(json!([])));
    assert!(e.iter().any(|x| x.contains("non-empty array")), "{e:?}");
}

// ---------------------------------------------------------------------------
// Manifests
// ---------------------------------------------------------------------------

fn manifest_errors(doc: &Value) -> Vec<String> {
    let mut e = Vec::new();
    check_manifest(doc, &mut e);
    e
}

#[test]
fn the_shipped_vm_manifest_is_valid() {
    assert_eq!(
        manifest_errors(&load("dlc/vm/dlc-manifest.json")),
        Vec::<String>::new()
    );
}

#[test]
fn manifests_reject_unknown_fields_bad_semver_and_bad_kinds() {
    let base = load("dlc/vm/dlc-manifest.json");

    let mut m = base.clone();
    m["bogus"] = json!(1);
    assert!(
        manifest_errors(&m)
            .iter()
            .any(|e| e.contains("unknown fields"))
    );

    let mut m = base.clone();
    m["version"] = json!("1.x");
    assert!(manifest_errors(&m).iter().any(|e| e.contains("semver")));

    let mut m = base.clone();
    m["kind"] = json!("nonsense");
    assert!(
        manifest_errors(&m)
            .iter()
            .any(|e| e.contains("kind must be one of"))
    );

    let mut m = base.clone();
    m["id"] = json!("Not_Kebab");
    assert!(
        manifest_errors(&m)
            .iter()
            .any(|e| e.contains("lowercase-kebab"))
    );

    let mut m = base.clone();
    m.as_object_mut().unwrap().remove("license");
    assert!(
        manifest_errors(&m)
            .iter()
            .any(|e| e.contains("missing required"))
    );
}

#[test]
fn edit_script_kind_and_payload_format_must_agree() {
    let mut m = json!({
        "id":"x","name":"X","version":"1.0.0","description":"d","license":"AGPL-3.0-or-later",
        "kind":"edit-script","payload":{"format":"idaptik-puzzles/1","path":"p.json"}
    });
    assert!(
        manifest_errors(&m)
            .iter()
            .any(|e| e.contains("requires payload.format idaptik-edit"))
    );

    m["kind"] = json!("puzzle-pack");
    m["payload"]["format"] = json!("idaptik-edit/1");
    assert!(
        manifest_errors(&m)
            .iter()
            .any(|e| e.contains("requires kind edit-script"))
    );
}

// ---------------------------------------------------------------------------
// Puzzles and vault sequences
// ---------------------------------------------------------------------------

fn puzzle_errors(doc: &Value) -> Vec<String> {
    let mut e = Vec::new();
    check_register_puzzle(doc, &mut e);
    e
}

#[test]
fn puzzles_reject_impossible_and_unknown_content() {
    let base = load("dlc/legacy-puzzles/beginner_01_simple_add.json");
    assert_eq!(puzzle_errors(&base), Vec::<String>::new());

    let mut p = base.clone();
    p["optimalMoves"] = json!(p["maxMoves"].as_i64().unwrap() + 1);
    assert!(
        puzzle_errors(&p)
            .iter()
            .any(|e| e.contains("optimalMoves must be <="))
    );

    let mut p = base.clone();
    p["allowedInstructions"]
        .as_array_mut()
        .unwrap()
        .push(json!("TELEPORT"));
    assert!(
        puzzle_errors(&p)
            .iter()
            .any(|e| e.contains("unknown instructions"))
    );

    let mut p = base.clone();
    let first = p["allowedInstructions"][0].clone();
    p["allowedInstructions"].as_array_mut().unwrap().push(first);
    assert!(
        puzzle_errors(&p)
            .iter()
            .any(|e| e.contains("must not repeat"))
    );

    let mut p = base.clone();
    p["difficulty"] = json!("trivial");
    assert!(
        puzzle_errors(&p)
            .iter()
            .any(|e| e.contains("difficulty must be one of"))
    );

    let mut p = base.clone();
    p["goalState"]["zz"] = json!(0);
    assert!(
        puzzle_errors(&p)
            .iter()
            .any(|e| e.contains("share one register set"))
    );

    let mut p = base.clone();
    p["metadata"]["created"] = json!("01/02/2026");
    assert!(puzzle_errors(&p).iter().any(|e| e.contains("YYYY-MM-DD")));

    let mut p = base.clone();
    p["hints"]
        .as_array_mut()
        .unwrap()
        .push(json!({"moveNumber":1}));
    assert!(puzzle_errors(&p).iter().any(|e| e.contains("hints[")));
}

#[test]
fn vault_sequences_reject_unknown_bits_and_malformed_ops() {
    let base = load("dlc/legacy-puzzles/vault_7.json");
    let mut e = Vec::new();
    check_vault_sequence(&base, &mut e);
    assert_eq!(e, Vec::<String>::new());

    let mut v = base.clone();
    v["steps"]
        .as_array_mut()
        .unwrap()
        .push(json!({"op":"flip","target":"ghost"}));
    let mut e = Vec::new();
    check_vault_sequence(&v, &mut e);
    assert!(e.iter().any(|x| x.contains("unknown bit 'ghost'")), "{e:?}");

    let mut v = base.clone();
    v["steps"]
        .as_array_mut()
        .unwrap()
        .push(json!({"op":"rotate","target":"a"}));
    let mut e = Vec::new();
    check_vault_sequence(&v, &mut e);
    assert!(e.iter().any(|x| x.contains("op must be one of")), "{e:?}");

    let mut v = base.clone();
    v["steps"]
        .as_array_mut()
        .unwrap()
        .push(json!({"op":"swap","targets":["a"]}));
    let mut e = Vec::new();
    check_vault_sequence(&v, &mut e);
    assert!(
        e.iter().any(|x| x.contains("exactly two bit names")),
        "{e:?}"
    );
}

// ---------------------------------------------------------------------------
// Dispatch and whole-tree
// ---------------------------------------------------------------------------

#[test]
fn classification_routes_each_shape_to_its_contract() {
    // A manifest is routed by filename; everything else by shape.
    let mut e = Vec::new();
    classify_and_check(
        Path::new("dlc/vm/dlc-manifest.json"),
        &load("dlc/vm/dlc-manifest.json"),
        &mut e,
    );
    assert_eq!(e, Vec::<String>::new());

    let mut e = Vec::new();
    classify_and_check(
        Path::new("x/edit-script.json"),
        &load("dlc/examples/ai-edit-sample/edit-script.json"),
        &mut e,
    );
    assert_eq!(e, Vec::<String>::new());
}

#[test]
fn every_shipped_dlc_artifact_validates() {
    let root = repo_root();
    let mut checked = 0;
    let mut stack = vec![root.join("dlc")];
    while let Some(d) = stack.pop() {
        for entry in std::fs::read_dir(&d).unwrap().flatten() {
            let p = entry.path();
            if p.is_dir() {
                stack.push(p);
            } else if p.extension().and_then(|e| e.to_str()) == Some("json") {
                let doc: Value =
                    serde_json::from_str(&std::fs::read_to_string(&p).unwrap()).unwrap();
                let mut errors = Vec::new();
                classify_and_check(&p, &doc, &mut errors);
                assert_eq!(errors, Vec::<String>::new(), "{}", p.display());
                checked += 1;
            }
        }
    }
    assert!(
        checked >= 30,
        "expected the full artifact set, saw {checked}"
    );
}
