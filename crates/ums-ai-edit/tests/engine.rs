// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
//! The behavioural contract of the AI-edit engine.
//!
//! Ported case-for-case from the Python suite this crate replaces
//! (`tests/test_ai_edit.py`), because that suite *was* the contract: a
//! rewrite that merely looks right proves nothing. Each block below names the
//! property it pins.

use serde_json::{Value, json};
use ums_ai_edit::microkanren::*;
use ums_ai_edit::{constraints, describe, engine, verbs, vocab};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn lobby_state() -> Term {
    let script = json!({"edits": [
        {"verb": "add_zone", "id": "lobby", "securityTier": 0, "worldXStart": 0, "worldXEnd": 40}
    ]});
    let (state, report) = engine::apply_edit_script(&verbs::initial_state(), &script);
    assert!(report.ok, "fixture must apply");
    state
}

fn apply(state: &Term, edits: Value) -> (Term, engine::Report) {
    engine::apply_edit_script(state, &json!({ "edits": edits }))
}

// ---------------------------------------------------------------------------
// microKanren kernel
// ---------------------------------------------------------------------------

#[test]
fn eq_unifies_a_fresh_variable() {
    let r = run(None, |q| eq(q, Term::Int(5)));
    assert_eq!(r, vec![Term::Int(5)]);
}

#[test]
fn fail_yields_no_answers() {
    let r = run(None, |_| fail());
    assert!(r.is_empty());
}

#[test]
fn succeed_yields_exactly_one_answer() {
    let r = run(None, |q| conj(vec![succeed(), eq(q, Term::Bool(true))]));
    assert_eq!(r.len(), 1);
}

#[test]
fn conj_requires_both_goals() {
    // Contradictory conjuncts have no model.
    let r = run(None, |q| {
        conj(vec![eq(q.clone(), Term::Int(1)), eq(q, Term::Int(2))])
    });
    assert!(r.is_empty());
}

#[test]
fn disj_yields_both_branches() {
    let r = run(None, |q| {
        disj(vec![eq(q.clone(), Term::Int(1)), eq(q, Term::Int(2))])
    });
    assert_eq!(r, vec![Term::Int(1), Term::Int(2)]);
}

#[test]
fn unify_is_structural_over_sequences() {
    let r = run(None, |q| {
        eq(
            Term::Seq(vec![Term::Int(1), q.clone(), Term::Int(3)]),
            Term::Seq(vec![Term::Int(1), Term::Int(2), Term::Int(3)]),
        )
    });
    assert_eq!(r, vec![Term::Int(2)]);
}

#[test]
fn unify_rejects_sequences_of_different_length() {
    let s = Subst::new();
    let out = unify(
        &Term::Seq(vec![Term::Int(1)]),
        &Term::Seq(vec![Term::Int(1), Term::Int(2)]),
        &s,
    );
    assert!(out.is_none());
}

#[test]
fn unify_requires_maps_to_have_the_same_keys() {
    let s = Subst::new();
    let a = Term::Map([("x".into(), Term::Int(1))].into_iter().collect());
    let b = Term::Map(
        [("x".into(), Term::Int(1)), ("y".into(), Term::Int(2))]
            .into_iter()
            .collect(),
    );
    assert!(unify(&a, &b, &s).is_none());
}

#[test]
fn walk_resolves_a_chain_of_variables() {
    let (x, y) = (Var::new("x"), Var::new("y"));
    let s = Subst::new();
    let s = unify(&Term::Var(x.clone()), &Term::Var(y.clone()), &s).unwrap();
    let s = unify(&Term::Var(y), &Term::Int(7), &s).unwrap();
    assert_eq!(walk(&Term::Var(x), &s), Term::Int(7));
}

#[test]
fn is_ground_sees_through_compounds() {
    assert!(is_ground(&Term::Seq(vec![Term::Int(1), Term::str("a")])));
    assert!(!is_ground(&Term::Seq(vec![
        Term::Int(1),
        Term::Var(Var::new("v"))
    ])));
}

#[test]
fn membero_enumerates_a_finite_domain_in_order() {
    let items = vec![Term::str("a"), Term::str("b"), Term::str("c")];
    let r = run(None, move |q| membero(q, &items));
    assert_eq!(r, vec![Term::str("a"), Term::str("b"), Term::str("c")]);
}

#[test]
fn take_bounds_the_number_of_answers() {
    let items: Vec<Term> = (0..100).map(Term::Int).collect();
    let r = run(Some(3), move |q| membero(q, &items));
    assert_eq!(r.len(), 3);
}

/// An infinite relation: `x` is a natural number >= n. Recursion is guarded
/// by `delay`, so each step builds an immature stream instead of diverging.
fn nats(x: Term, n: i64) -> Goal {
    disj(vec![
        eq(x.clone(), Term::Int(n)),
        delay(move || nats(x.clone(), n + 1)),
    ])
}

#[test]
fn a_finite_disjunction_concatenates() {
    // mplus only interleaves at IMMATURE points. A disjunction of `eq` goals
    // is fully mature, so it concatenates — matching the reference kernel
    // exactly (verified against the Python original, which returns the same
    // sequence). Pinned here so an "improvement" to mplus cannot silently
    // change search order, which callers depend on: solve() enumerates
    // vocabularies in declared order.
    let many: Vec<Term> = (0..50).map(Term::Int).collect();
    let r = run(Some(4), move |q| {
        disj(vec![
            membero(q.clone(), &many),
            eq(q, Term::str("right-branch")),
        ])
    });
    assert_eq!(
        r,
        vec![Term::Int(0), Term::Int(1), Term::Int(2), Term::Int(3)]
    );
}

#[test]
fn mplus_interleaves_at_immature_points_so_disj_stays_complete() {
    // With an infinite left branch, concatenation would starve the right one
    // forever. Interleaving is what keeps disj complete. The exact sequence
    // is the reference kernel's: [0, right-branch, 1, 2].
    let r = run(Some(4), |q| {
        disj(vec![nats(q.clone(), 0), eq(q, Term::str("right-branch"))])
    });
    assert_eq!(
        r,
        vec![
            Term::Int(0),
            Term::str("right-branch"),
            Term::Int(1),
            Term::Int(2)
        ],
        "interleaving lost: an infinite branch starved the other"
    );
}

#[test]
fn delay_makes_an_infinite_relation_usable() {
    let r = run(Some(5), |q| nats(q, 10));
    assert_eq!(
        r,
        vec![
            Term::Int(10),
            Term::Int(11),
            Term::Int(12),
            Term::Int(13),
            Term::Int(14)
        ]
    );
}

#[test]
fn reify_names_unbound_variables() {
    let r = run(None, |q| {
        eq(
            q,
            Term::Seq(vec![Term::Var(Var::new("free")), Term::Int(1)]),
        )
    });
    assert_eq!(r, vec![Term::Seq(vec![Term::str("_0"), Term::Int(1)])]);
}

#[test]
fn fresh_macro_introduces_distinct_variables() {
    let r = ums_ai_edit::fresh!(x, y => {
        let (xc, yc) = (x.clone(), y.clone());
        run(None, move |q| {
            conj(vec![
                eq(xc.clone(), Term::Int(1)),
                eq(yc.clone(), xc.clone()),
                eq(q, yc.clone()),
            ])
        })
    });
    assert_eq!(r, vec![Term::Int(1)]);
}

#[test]
fn int_and_float_unify_across_the_json_number_tower() {
    // The wire format is JSON, where 40 and 40.0 denote the same value.
    let s = Subst::new();
    assert!(unify(&Term::Int(40), &Term::Num(40.0), &s).is_some());
}

// ---------------------------------------------------------------------------
// Vocabularies (generated from config/vocab.ncl)
// ---------------------------------------------------------------------------

#[test]
fn vocabularies_have_their_declared_sizes() {
    assert_eq!(vocab::DEVICE_KINDS.len(), 12);
    assert_eq!(vocab::GUARD_RANKS.len(), 8);
    assert_eq!(vocab::DOG_BREEDS.len(), 3);
    assert_eq!(vocab::DRONE_ARCHETYPES.len(), 3);
    assert_eq!(vocab::WIRING_TYPES.len(), 5);
    assert_eq!(vocab::NPC_ROLES.len(), 8);
    assert_eq!(vocab::CHARACTER_ARCHETYPES.len(), 8);
    assert_eq!(vocab::CHARACTER_MODIFIERS.len(), 8);
    assert_eq!(vocab::ITEM_CATEGORIES.len(), 8);
    assert_eq!(vocab::ZONE_SEGMENTS.len(), 8);
}

#[test]
fn every_vocabulary_is_a_set() {
    for (name, v) in [
        ("device_kinds", &vocab::DEVICE_KINDS[..]),
        ("guard_ranks", &vocab::GUARD_RANKS[..]),
        ("dog_breeds", &vocab::DOG_BREEDS[..]),
        ("drone_archetypes", &vocab::DRONE_ARCHETYPES[..]),
        ("wiring_types", &vocab::WIRING_TYPES[..]),
        ("npc_roles", &vocab::NPC_ROLES[..]),
        ("character_archetypes", &vocab::CHARACTER_ARCHETYPES[..]),
        ("character_modifiers", &vocab::CHARACTER_MODIFIERS[..]),
        ("item_categories", &vocab::ITEM_CATEGORIES[..]),
        ("zone_segments", &vocab::ZONE_SEGMENTS[..]),
    ] {
        let mut sorted = v.to_vec();
        sorted.sort_unstable();
        let before = sorted.len();
        sorted.dedup();
        assert_eq!(sorted.len(), before, "{name} contains a duplicate");
    }
}

#[test]
fn the_registry_declares_ten_verbs() {
    assert_eq!(vocab::VERBS.len(), 10);
    assert!(vocab::verb("add_guard").is_some());
    assert!(vocab::verb("teleport_guard").is_none());
}

// ---------------------------------------------------------------------------
// Verbs
// ---------------------------------------------------------------------------

#[test]
fn initial_state_satisfies_the_proofs() {
    assert!(engine::satisfiable(&verbs::initial_state()));
}

#[test]
fn initial_state_declares_every_level_key() {
    let s = verbs::initial_state();
    for key in verbs::LEVEL_KEYS {
        assert!(s.get(key).is_some(), "missing level key {key}");
    }
}

#[test]
fn add_zone_appends_a_zone() {
    let (state, report) = apply(
        &verbs::initial_state(),
        json!([{"verb":"add_zone","id":"lobby","securityTier":0,"worldXStart":0,"worldXEnd":40}]),
    );
    assert!(report.ok);
    assert_eq!(state.get("zones").unwrap().as_seq().unwrap().len(), 1);
}

#[test]
fn verbs_do_not_mutate_the_input_state() {
    let before = verbs::initial_state();
    let (after, report) = apply(
        &before,
        json!([{"verb":"add_zone","id":"z","securityTier":0,"worldXStart":0,"worldXEnd":1}]),
    );
    assert!(report.ok);
    assert!(before.get("zones").unwrap().as_seq().unwrap().is_empty());
    assert_eq!(after.get("zones").unwrap().as_seq().unwrap().len(), 1);
}

#[test]
fn add_zone_accepts_an_optional_segment_override() {
    let (state, report) = apply(
        &verbs::initial_state(),
        json!([{"verb":"add_zone","id":"sr","securityTier":2,"worldXStart":0,"worldXEnd":9,"segment":"Internal"}]),
    );
    assert!(report.ok, "{:?}", report.steps);
    let zone = &state.get("zones").unwrap().as_seq().unwrap()[0];
    assert_eq!(zone.get("segment").unwrap().as_str(), Some("Internal"));
}

#[test]
fn an_absent_optional_argument_is_omitted_not_nulled() {
    let (state, _) = apply(
        &verbs::initial_state(),
        json!([{"verb":"add_zone","id":"z","securityTier":0,"worldXStart":0,"worldXEnd":1}]),
    );
    let zone = &state.get("zones").unwrap().as_seq().unwrap()[0];
    assert!(
        zone.get("segment").is_none(),
        "an unspecified segment must not reach the wire as an explicit null"
    );
}

#[test]
fn add_device_rejects_an_unknown_device_kind() {
    let state = lobby_state();
    let (_, report) = apply(
        &state,
        json!([{"verb":"add_device","id":"d","kind":"Toaster","zone":"lobby","worldX":1}]),
    );
    assert!(!report.ok);
}

#[test]
fn set_physical_lifts_the_pbx_triple_to_the_top_level() {
    let state = lobby_state();
    let (state, report) = apply(
        &state,
        json!([
            {"verb":"add_device","id":"pbx","kind":"PhoneSystem","zone":"lobby","worldX":1},
            {"verb":"set_physical","physical":{"hasPBX":true,"pbxIp":"10.0.0.1","pbxWorldX":1}}
        ]),
    );
    assert!(report.ok, "{:?}", report.steps);
    assert_eq!(state.get("pbxIp").unwrap().as_str(), Some("10.0.0.1"));
    assert!(state.get("hasPBX").unwrap().is_truthy());
}

#[test]
fn set_mission_replaces_the_opaque_mission_block() {
    let (state, report) = apply(
        &verbs::initial_state(),
        json!([{"verb":"set_mission","mission":{"objective":"exfiltrate"}}]),
    );
    assert!(report.ok);
    assert_eq!(
        state
            .get("mission")
            .unwrap()
            .get("objective")
            .unwrap()
            .as_str(),
        Some("exfiltrate")
    );
}

// ---------------------------------------------------------------------------
// The six validity proofs
// ---------------------------------------------------------------------------

fn holds(goal_of: impl Fn(Term) -> Goal, state: &Term) -> bool {
    !run(Some(1), |q| {
        conj(vec![goal_of(state.clone()), eq(q, Term::Bool(true))])
    })
    .is_empty()
}

#[test]
fn guards_in_zones_rejects_an_actor_in_an_undeclared_zone() {
    let state = lobby_state();
    let (_, report) = apply(
        &state,
        json!([{"verb":"add_guard","id":"g","rank":"Sentinel","zone":"atlantis"}]),
    );
    assert!(!report.ok, "a guard in an undeclared zone must be refused");
}

#[test]
fn zones_ordered_rejects_an_inverted_interval() {
    let state = json!({
        "zones":[{"id":"z","securityTier":0,"worldXStart":40,"worldXEnd":0}],
        "devices":[],"guards":[],"dogs":[],"drones":[],"assassins":[],"items":[],
        "npcs":[],"characters":[],"wiring":[],"zoneTransitions":[],"deviceDefences":[],
        "mission":null,"physical":null,"hasPBX":false,"pbxIp":null,"pbxWorldX":null
    });
    assert!(!holds(
        constraints::zones_ordered,
        &engine::from_json(&state)
    ));
}

#[test]
fn zones_ordered_rejects_overlapping_zones() {
    let state = lobby_state();
    let (_, report) = apply(
        &state,
        json!([{"verb":"add_zone","id":"overlap","securityTier":1,"worldXStart":20,"worldXEnd":60}]),
    );
    assert!(!report.ok, "overlapping worldX intervals must be refused");
}

#[test]
fn zones_ordered_rejects_a_tier_that_decreases_with_depth() {
    let state = lobby_state(); // lobby: tier 0, x 0..40
    let (_, report) = apply(
        &state,
        json!([{"verb":"add_zone","id":"deeper","securityTier":0,"worldXStart":40,"worldXEnd":80}]),
    );
    assert!(report.ok, "an equal tier deeper in is allowed");

    let (_, report) = apply(
        &engine::from_json(&json!({
            "zones":[{"id":"outer","securityTier":3,"worldXStart":0,"worldXEnd":40}],
            "devices":[],"guards":[],"dogs":[],"drones":[],"assassins":[],"items":[],
            "npcs":[],"characters":[],"wiring":[],"zoneTransitions":[],"deviceDefences":[],
            "mission":null,"physical":null,"hasPBX":false,"pbxIp":null,"pbxWorldX":null
        })),
        json!([{"verb":"add_zone","id":"inner","securityTier":1,"worldXStart":40,"worldXEnd":80}]),
    );
    assert!(!report.ok, "a tier must not decrease as worldX increases");
}

#[test]
fn zones_ordered_accepts_abutting_intervals() {
    let state = lobby_state();
    let (_, report) = apply(
        &state,
        json!([{"verb":"add_zone","id":"next","securityTier":1,"worldXStart":40,"worldXEnd":80}]),
    );
    assert!(report.ok, "touching-but-not-overlapping zones are legal");
}

#[test]
fn pbx_consistent_requires_a_phone_system_device() {
    let state = lobby_state();
    // hasPBX with an IP and a position, but no PhoneSystem device.
    let (_, report) = apply(
        &state,
        json!([{"verb":"set_physical","physical":{"hasPBX":true,"pbxIp":"10.0.0.1","pbxWorldX":1}}]),
    );
    assert!(
        !report.ok,
        "hasPBX without a PhoneSystem device must be refused"
    );
}

#[test]
fn pbx_consistent_rejects_dangling_fields_without_haspbx() {
    let state = lobby_state();
    let (_, report) = apply(
        &state,
        json!([{"verb":"set_physical","physical":{"hasPBX":false,"pbxIp":"10.0.0.1"}}]),
    );
    assert!(!report.ok, "a PBX IP with hasPBX false is dangling");
}

#[test]
fn devices_exist_rejects_a_device_in_an_undeclared_zone() {
    let state = lobby_state();
    let (_, report) = apply(
        &state,
        json!([{"verb":"add_device","id":"d","kind":"Server","zone":"nowhere","worldX":1}]),
    );
    assert!(!report.ok);
}

#[test]
fn devices_exist_rejects_wiring_with_an_unknown_type() {
    let state = engine::from_json(&json!({
        "zones":[{"id":"z","securityTier":0,"worldXStart":0,"worldXEnd":10}],
        "devices":[{"id":"a","kind":"Server","zone":"z","worldX":1},
                   {"id":"b","kind":"Switch","zone":"z","worldX":2}],
        "wiring":[{"type":"StringAndTin","from":"a","to":"b"}],
        "guards":[],"dogs":[],"drones":[],"assassins":[],"items":[],"npcs":[],
        "characters":[],"zoneTransitions":[],"deviceDefences":[],
        "mission":null,"physical":null,"hasPBX":false,"pbxIp":null,"pbxWorldX":null
    }));
    assert!(!holds(constraints::devices_exist, &state));
}

#[test]
fn defence_targets_must_reference_an_existing_device() {
    let state = engine::from_json(&json!({
        "zones":[],"devices":[],"deviceDefences":[{"target":"ghost"}],
        "guards":[],"dogs":[],"drones":[],"assassins":[],"items":[],"npcs":[],
        "characters":[],"wiring":[],"zoneTransitions":[],
        "mission":null,"physical":null,"hasPBX":false,"pbxIp":null,"pbxWorldX":null
    }));
    assert!(!holds(constraints::defence_targets_exist, &state));
}

#[test]
fn items_in_zones_rejects_orphaned_loot() {
    let state = lobby_state();
    let (_, report) = apply(
        &state,
        json!([{"verb":"add_item","id":"loot","category":"Loot","zone":"void"}]),
    );
    assert!(!report.ok);
}

#[test]
fn all_six_proofs_are_named() {
    assert_eq!(constraints::NAMES.len(), 6);
}

// ---------------------------------------------------------------------------
// The engine: checking direction
// ---------------------------------------------------------------------------

#[test]
fn an_unknown_verb_is_rejected_and_named() {
    let (_, report) = apply(&verbs::initial_state(), json!([{"verb":"summon_dragon"}]));
    assert!(!report.ok);
    assert!(
        report.steps[0]
            .reason
            .as_ref()
            .unwrap()
            .contains("unknown verb")
    );
}

#[test]
fn a_missing_required_argument_is_rejected_and_named() {
    let (_, report) = apply(
        &verbs::initial_state(),
        json!([{"verb":"add_guard","id":"g"}]),
    );
    assert!(!report.ok);
    assert!(
        report.steps[0]
            .reason
            .as_ref()
            .unwrap()
            .contains("missing arguments")
    );
}

#[test]
fn apply_refuses_a_fresh_placeholder() {
    let state = lobby_state();
    let (_, report) = apply(
        &state,
        json!([{"verb":"add_guard","id":"g","rank":"?","zone":"lobby"}]),
    );
    assert!(!report.ok);
    assert!(report.steps[0].reason.as_ref().unwrap().contains("solve()"));
}

#[test]
fn a_script_is_rejected_at_the_failing_verb_and_earlier_work_is_kept() {
    let state = lobby_state();
    let (out, report) = apply(
        &state,
        json!([
            {"verb":"add_item","id":"ok","category":"Tool","zone":"lobby"},
            {"verb":"add_item","id":"bad","category":"Tool","zone":"nowhere"},
            {"verb":"add_item","id":"never","category":"Tool","zone":"lobby"}
        ]),
    );
    assert!(!report.ok);
    assert_eq!(
        report.applied, 1,
        "the first verb applied, the second failed"
    );
    assert_eq!(report.steps.len(), 2, "the third verb was never attempted");
    assert_eq!(out.get("items").unwrap().as_seq().unwrap().len(), 1);
}

#[test]
fn replaying_a_script_is_deterministic() {
    let a = apply(&verbs::initial_state(), sample_edits()).0;
    let b = apply(&verbs::initial_state(), sample_edits()).0;
    assert_eq!(engine::to_json(&a), engine::to_json(&b));
}

fn sample_edits() -> Value {
    json!([
        {"verb":"add_zone","id":"lobby","securityTier":0,"worldXStart":0,"worldXEnd":40},
        {"verb":"add_device","id":"cam","kind":"Camera","zone":"lobby","worldX":4},
        {"verb":"add_guard","id":"g","rank":"Sentinel","zone":"lobby"}
    ])
}

#[test]
fn the_shipped_sample_edit_script_replays_clean() {
    let text = std::fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../dlc/examples/ai-edit-sample/edit-script.json"
    ))
    .expect("sample artifact must exist");
    let script: Value = serde_json::from_str(&text).unwrap();
    let (_, report) = engine::apply_edit_script(&verbs::initial_state(), &script);
    assert!(report.ok, "sample rejected at {:?}", report.steps.last());
    assert_eq!(report.applied, report.total);
}

// ---------------------------------------------------------------------------
// The engine: generative direction
// ---------------------------------------------------------------------------

#[test]
fn solve_enumerates_a_finite_domain_in_declared_order() {
    let state = lobby_state();
    let proposals = engine::solve(
        &state,
        &json!({"verb":"add_dog","id":"d","breed":"?","zone":"?"}),
        10,
    )
    .unwrap();
    let breeds: Vec<&str> = proposals
        .iter()
        .map(|p| p.edit.get("breed").unwrap().as_str().unwrap())
        .collect();
    assert_eq!(breeds, vocab::DOG_BREEDS.to_vec());
}

#[test]
fn solve_only_proposes_constraint_satisfying_edits() {
    let state = lobby_state();
    let proposals = engine::solve(
        &state,
        &json!({"verb":"add_guard","id":"g","rank":"?","zone":"?"}),
        20,
    )
    .unwrap();
    assert!(!proposals.is_empty());
    for p in &proposals {
        assert!(
            engine::satisfiable(&p.state),
            "solve proposed a state that violates the proofs: {:?}",
            p.edit
        );
        // The zone can only be one that exists: narrowing, not filtering.
        assert_eq!(p.edit.get("zone").unwrap().as_str(), Some("lobby"));
    }
}

#[test]
fn solve_rejects_an_unknown_verb() {
    let e = engine::solve(&verbs::initial_state(), &json!({"verb":"nope"}), 1).unwrap_err();
    assert!(matches!(e, engine::SolveError::UnknownVerb(_)));
}

#[test]
fn solve_reports_a_missing_argument() {
    let e = engine::solve(&lobby_state(), &json!({"verb":"add_guard","rank":"?"}), 1).unwrap_err();
    assert!(matches!(e, engine::SolveError::MissingArgument { .. }));
}

#[test]
fn solve_refuses_to_invent_an_id() {
    // Ids and geometry are the proposer's job; the kernel has no domain for
    // them and must say so rather than guess.
    let e = engine::solve(
        &lobby_state(),
        &json!({"verb":"add_guard","id":"?","rank":"Sentinel","zone":"lobby"}),
        1,
    )
    .unwrap_err();
    assert!(matches!(e, engine::SolveError::NoFiniteDomain { .. }));
}

#[test]
fn solve_returns_nothing_when_no_zone_exists() {
    // With no declared zone the zone domain is empty, so there is no model —
    // refusal, not a fabricated zone.
    let proposals = engine::solve(
        &verbs::initial_state(),
        &json!({"verb":"add_guard","id":"g","rank":"?","zone":"?"}),
        5,
    )
    .unwrap();
    assert!(proposals.is_empty());
}

#[test]
fn solve_respects_the_requested_bound() {
    let state = lobby_state();
    let proposals = engine::solve(
        &state,
        &json!({"verb":"add_item","id":"i","category":"?","zone":"?"}),
        3,
    )
    .unwrap();
    assert_eq!(proposals.len(), 3);
}

#[test]
fn solve_pairs_two_fresh_vocabularies() {
    let state = lobby_state();
    let proposals = engine::solve(
        &state,
        &json!({"verb":"add_character","id":"c","archetype":"?","modifier":"?","zone":"?"}),
        4,
    )
    .unwrap();
    assert_eq!(proposals.len(), 4);
    for p in &proposals {
        let a = p.edit.get("archetype").unwrap().as_str().unwrap();
        let m = p.edit.get("modifier").unwrap().as_str().unwrap();
        assert!(vocab::CHARACTER_ARCHETYPES.contains(&a));
        assert!(vocab::CHARACTER_MODIFIERS.contains(&m));
    }
}

// ---------------------------------------------------------------------------
// JSON round-trip and reflection
// ---------------------------------------------------------------------------

#[test]
fn json_round_trips_through_the_term_language() {
    let v = json!({"a":[1,2.5,"x",true,null],"b":{"c":-3}});
    assert_eq!(engine::to_json(&engine::from_json(&v)), v);
}

#[test]
fn describe_reports_every_verb_and_vocabulary() {
    let d = describe::describe();
    assert_eq!(d["names"].as_array().unwrap().len(), 10);
    assert_eq!(d["constraints"].as_array().unwrap().len(), 6);
    assert_eq!(
        d["vocabularies"]["device_kinds"].as_array().unwrap().len(),
        12
    );
    assert_eq!(d["fresh_placeholder"], json!("?"));
}

#[test]
fn describe_argument_order_matches_the_registry() {
    let d = describe::describe();
    for spec in vocab::VERBS.iter() {
        let reported: Vec<&str> = d["arg_order"][spec.name]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_str().unwrap())
            .collect();
        assert_eq!(
            reported,
            spec.args.to_vec(),
            "{} reflects a different argument order than it dispatches on",
            spec.name
        );
    }
}
