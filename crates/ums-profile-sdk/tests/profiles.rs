// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

use serde_json::{Value, json};
use ums_profile_sdk::{
    PROFILE_API_VERSION, ProfileRegistry, SimulationAdapter, chronicles_of_slavia, idaptik,
    is_profile_id, is_semver,
};

#[test]
fn built_in_profiles_register_with_valid_ids_and_versions() {
    let registry = ProfileRegistry::with_builtins();
    let profiles: Vec<_> = registry.iter().collect();
    assert_eq!(profiles.len(), 2);
    for profile in profiles {
        assert_eq!(profile.api_version, PROFILE_API_VERSION);
        assert!(is_profile_id(&profile.profile_id));
        assert!(is_semver(&profile.version));
        assert_eq!(profile.validate(), Ok(()));
    }
}

#[test]
fn duplicate_profile_registration_is_rejected() {
    let mut registry = ProfileRegistry::default();
    registry.register(idaptik()).unwrap();
    let error = registry.register(idaptik()).unwrap_err();
    assert!(error.0.contains("already registered"));
}

#[test]
fn malformed_profile_id_and_version_are_rejected() {
    let mut profile = idaptik().clone();
    profile.profile_id = "IDApTIK Profile".into();
    profile.version = "next".into();
    let errors = profile.validate().unwrap_err();
    assert!(errors.iter().any(|error| error.0.contains("profileId")));
    assert!(errors.iter().any(|error| error.0.contains("semantic")));
}

#[test]
fn idaptik_vocabulary_and_verb_resolution_are_profile_owned() {
    let profile = idaptik();
    assert!(profile.vocabulary_contains("device-kinds", "PhoneSystem"));
    assert!(profile.vocabulary_contains("guard-ranks", "AntiHacker"));
    assert!(profile.edit_verb("add_guard").is_some());
    assert!(profile.edit_verb("stabilise_bridge").is_none());
}

#[test]
fn slavia_vocabulary_and_verb_resolution_are_profile_owned() {
    let profile = chronicles_of_slavia();
    assert!(profile.vocabulary_contains("heroine-influences", "Quickening"));
    assert!(profile.vocabulary_contains("world-disruptions", "RiftCorruption"));
    assert!(profile.edit_verb("stabilise_bridge").is_some());
    assert!(profile.edit_verb("add_guard").is_none());
}

#[test]
fn profile_terms_do_not_leak_across_games() {
    assert!(!chronicles_of_slavia().vocabulary_contains("guard-ranks", "AntiHacker"));
    assert!(!idaptik().vocabulary_contains("world-disruptions", "RiftCorruption"));
}

struct DeterministicPreview;

impl SimulationAdapter for DeterministicPreview {
    fn preview(&self, model: &Value, seed: u64) -> Result<Value, String> {
        Ok(json!({"seed": seed, "model": model, "trace": ["accepted"]}))
    }
}

#[test]
fn simulation_adapter_contract_is_deterministic_for_the_same_seed() {
    let adapter = DeterministicPreview;
    let model = json!({"entities": [{"id": "stable"}]});
    assert_eq!(
        adapter.preview(&model, 42).unwrap(),
        adapter.preview(&model, 42).unwrap()
    );
}

#[test]
fn minimal_fixtures_name_their_profile_and_stay_isolated() {
    let idaptik_fixture: Value = serde_json::from_str(include_str!(
        "../../../profiles/idaptik/tests/minimal-level.json"
    ))
    .unwrap();
    let slavia_fixture: Value = serde_json::from_str(include_str!(
        "../../../profiles/chronicles-of-slavia/tests/zone-a.json"
    ))
    .unwrap();
    assert_eq!(idaptik_fixture["profile"], "idaptik");
    assert_eq!(slavia_fixture["profile"], "chronicles-of-slavia");
    assert!(idaptik_fixture.to_string().contains("securityTier"));
    assert!(!idaptik_fixture.to_string().contains("Rift"));
    assert!(slavia_fixture.to_string().contains("grove-birds"));
    assert!(!slavia_fixture.to_string().contains("AntiHacker"));
}
