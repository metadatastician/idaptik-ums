// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>

//! Typed, versioned, reflective contracts between Universal Modding Studio
//! and a game profile.
//!
//! A profile is data first: its checked reflection document describes the
//! vocabulary, component palette, edit surface, constraints, capabilities,
//! UI contributions and integration contracts that a future studio can
//! inspect without knowing the game. Executable services implement the narrow
//! traits below; loading arbitrary code is deliberately not part of v1.

#![forbid(unsafe_code)]

use std::collections::{BTreeMap, BTreeSet};
use std::sync::OnceLock;

use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const PROFILE_API_VERSION: &str = "ums-profile/1";

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProfileDescriptor {
    pub api_version: String,
    pub profile_id: String,
    pub version: String,
    pub target_game: TargetGame,
    pub vocabularies: BTreeMap<String, Vec<String>>,
    pub component_types: Vec<ComponentType>,
    pub edit_verbs: Vec<EditVerb>,
    pub constraints: Vec<NamedContract>,
    pub capabilities: Vec<String>,
    pub generators: Vec<NamedContract>,
    pub importers: Vec<FormatContract>,
    pub exporters: Vec<FormatContract>,
    pub inspectors: Vec<UiContribution>,
    pub canvas_lenses: Vec<UiContribution>,
    pub simulation_adapter: Option<NamedContract>,
    pub package_compiler: Option<NamedContract>,
    pub runtime_contract: Option<NamedContract>,
    pub migrations: Vec<Migration>,
    pub tests: Vec<NamedContract>,
    pub guarantees: Vec<Guarantee>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TargetGame {
    pub id: String,
    pub name: String,
    pub compatible_versions: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ComponentType {
    pub id: String,
    pub label: String,
    pub fields: Vec<Field>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Field {
    pub id: String,
    pub value_type: String,
    pub vocabulary: Option<String>,
    pub required: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EditVerb {
    pub id: String,
    pub collection: String,
    pub summary: String,
    pub arguments: Vec<Field>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct NamedContract {
    pub id: String,
    pub version: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct FormatContract {
    pub id: String,
    pub format: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct UiContribution {
    pub id: String,
    pub label: String,
    pub applies_to: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Migration {
    pub from: String,
    pub to: String,
    pub id: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Guarantee {
    pub id: String,
    pub level: GuaranteeLevel,
    pub evidence: String,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum GuaranteeLevel {
    MachineChecked,
    RuntimeValidated,
    Tested,
    Designed,
    Aspirational,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProfileError(pub String);

impl std::fmt::Display for ProfileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for ProfileError {}

impl ProfileDescriptor {
    pub fn validate(&self) -> Result<(), Vec<ProfileError>> {
        let mut errors = Vec::new();
        if self.api_version != PROFILE_API_VERSION {
            errors.push(ProfileError(format!(
                "unsupported profile API '{}'; expected {PROFILE_API_VERSION}",
                self.api_version
            )));
        }
        if !is_profile_id(&self.profile_id) {
            errors.push(ProfileError(
                "profileId must be lowercase dotted-kebab".into(),
            ));
        }
        if !is_semver(&self.version) {
            errors.push(ProfileError("profile version must be semantic".into()));
        }
        if self.target_game.compatible_versions.is_empty() {
            errors.push(ProfileError(
                "targetGame.compatibleVersions must not be empty".into(),
            ));
        }

        unique_ids(
            "component type",
            self.component_types.iter().map(|x| &x.id),
            is_profile_id,
            &mut errors,
        );
        unique_ids(
            "edit verb",
            self.edit_verbs.iter().map(|x| &x.id),
            is_verb_id,
            &mut errors,
        );
        unique_ids(
            "capability",
            self.capabilities.iter(),
            is_profile_id,
            &mut errors,
        );

        for (name, members) in &self.vocabularies {
            if !is_profile_id(name) {
                errors.push(ProfileError(format!("invalid vocabulary id '{name}'")));
            }
            if members.is_empty() {
                errors.push(ProfileError(format!("vocabulary '{name}' is empty")));
            }
            let unique: BTreeSet<&String> = members.iter().collect();
            if unique.len() != members.len() {
                errors.push(ProfileError(format!(
                    "vocabulary '{name}' contains duplicates"
                )));
            }
        }

        for verb in &self.edit_verbs {
            for arg in &verb.arguments {
                validate_field_vocabulary("verb", &verb.id, arg, &self.vocabularies, &mut errors);
            }
        }
        for component in &self.component_types {
            for field in &component.fields {
                validate_field_vocabulary(
                    "component",
                    &component.id,
                    field,
                    &self.vocabularies,
                    &mut errors,
                );
            }
        }

        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors)
        }
    }

    pub fn vocabulary_contains(&self, vocabulary: &str, term: &str) -> bool {
        self.vocabularies
            .get(vocabulary)
            .is_some_and(|members| members.iter().any(|member| member == term))
    }

    pub fn edit_verb(&self, id: &str) -> Option<&EditVerb> {
        self.edit_verbs.iter().find(|verb| verb.id == id)
    }

    pub fn reflection(&self) -> Value {
        serde_json::to_value(self).expect("profile descriptor is serializable")
    }
}

fn validate_field_vocabulary(
    owner_kind: &str,
    owner_id: &str,
    field: &Field,
    vocabularies: &BTreeMap<String, Vec<String>>,
    errors: &mut Vec<ProfileError>,
) {
    if let Some(vocabulary) = &field.vocabulary
        && !vocabularies.contains_key(vocabulary)
    {
        errors.push(ProfileError(format!(
            "{owner_kind} '{owner_id}' references unknown vocabulary '{vocabulary}'"
        )));
    }
}

fn unique_ids<'a>(
    kind: &str,
    ids: impl Iterator<Item = &'a String>,
    valid: impl Fn(&str) -> bool,
    errors: &mut Vec<ProfileError>,
) {
    let mut seen = BTreeSet::new();
    for id in ids {
        if !valid(id) {
            errors.push(ProfileError(format!("invalid {kind} id '{id}'")));
        }
        if !seen.insert(id) {
            errors.push(ProfileError(format!("duplicate {kind} id '{id}'")));
        }
    }
}

/// Edit verbs preserve existing wire identifiers such as `add_zone`.
pub fn is_verb_id(value: &str) -> bool {
    !value.is_empty()
        && value.chars().next().is_some_and(|c| c.is_ascii_lowercase())
        && value
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
}

pub fn is_profile_id(value: &str) -> bool {
    !value.is_empty()
        && value.split('.').all(|part| {
            !part.is_empty()
                && part
                    .chars()
                    .next()
                    .is_some_and(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
                && part
                    .chars()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
        })
}

pub fn is_semver(value: &str) -> bool {
    let core = value.split(['-', '+']).next().unwrap_or("");
    let parts: Vec<&str> = core.split('.').collect();
    parts.len() == 3
        && parts
            .iter()
            .all(|part| !part.is_empty() && part.chars().all(|c| c.is_ascii_digit()))
}

fn load(text: &str) -> ProfileDescriptor {
    let descriptor: ProfileDescriptor =
        serde_json::from_str(text).expect("checked in profile reflection must parse");
    descriptor
        .validate()
        .expect("checked in profile reflection must satisfy the profile API");
    descriptor
}

pub fn idaptik() -> &'static ProfileDescriptor {
    static PROFILE: OnceLock<ProfileDescriptor> = OnceLock::new();
    PROFILE.get_or_init(|| load(include_str!("../../../profiles/idaptik/profile.json")))
}

pub fn chronicles_of_slavia() -> &'static ProfileDescriptor {
    static PROFILE: OnceLock<ProfileDescriptor> = OnceLock::new();
    PROFILE.get_or_init(|| {
        load(include_str!(
            "../../../profiles/chronicles-of-slavia/profile.json"
        ))
    })
}

#[derive(Default)]
pub struct ProfileRegistry {
    profiles: BTreeMap<String, &'static ProfileDescriptor>,
}

impl ProfileRegistry {
    pub fn with_builtins() -> Self {
        let mut registry = Self::default();
        registry
            .register(idaptik())
            .expect("IDApTIK profile is valid");
        registry
            .register(chronicles_of_slavia())
            .expect("Chronicles of Slavia profile is valid");
        registry
    }

    pub fn register(&mut self, profile: &'static ProfileDescriptor) -> Result<(), ProfileError> {
        profile
            .validate()
            .map_err(|errors| ProfileError(errors[0].0.clone()))?;
        if self.profiles.contains_key(&profile.profile_id) {
            return Err(ProfileError(format!(
                "profile '{}' is already registered",
                profile.profile_id
            )));
        }
        self.profiles.insert(profile.profile_id.clone(), profile);
        Ok(())
    }

    pub fn get(&self, profile_id: &str) -> Option<&'static ProfileDescriptor> {
        self.profiles.get(profile_id).copied()
    }

    pub fn iter(&self) -> impl Iterator<Item = &'static ProfileDescriptor> + '_ {
        self.profiles.values().copied()
    }
}

/// Executable services remain typed and host-controlled. A profile package
/// may provide implementations through an explicit integration crate; v1
/// does not dynamically execute code named by reflection data.
pub trait ProfileValidator: Send + Sync {
    fn validate(&self, model: &Value) -> Vec<String>;
}

pub trait ProfileGenerator: Send + Sync {
    fn generate(&self, request: &Value) -> Result<Value, String>;
}

pub trait ProfileImporter: Send + Sync {
    fn import(&self, source: &[u8]) -> Result<Value, String>;
}

pub trait ProfileExporter: Send + Sync {
    fn export(&self, model: &Value) -> Result<Vec<u8>, String>;
}

pub trait ProfileCompiler: Send + Sync {
    fn compile(&self, model: &Value, manifest: &Value) -> Result<Vec<u8>, String>;
}

pub trait SimulationAdapter: Send + Sync {
    fn preview(&self, model: &Value, seed: u64) -> Result<Value, String>;
}
