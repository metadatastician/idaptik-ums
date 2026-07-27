//! Data-driven UMS game profiles.
//!
//! This crate knows the generic profile protocol. Game vocabulary stays in
//! `profiles/<game>/`; the IDApTIK compiler consumes the game's published
//! contract metadata and scenario artifact instead of re-declaring its Rust
//! types here.

#![forbid(unsafe_code)]

use serde_json::{Map, Value, json};
use std::collections::BTreeSet;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug)]
pub enum ProfileError {
    Io { path: PathBuf, error: String },
    Json { path: PathBuf, error: String },
    Invalid(Vec<String>),
}

impl fmt::Display for ProfileError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io { path, error } => write!(f, "{}: {error}", path.display()),
            Self::Json { path, error } => write!(f, "{}: {error}", path.display()),
            Self::Invalid(errors) => write!(f, "{}", errors.join("; ")),
        }
    }
}

impl std::error::Error for ProfileError {}

fn read_json(path: &Path) -> Result<Value, ProfileError> {
    let text = fs::read_to_string(path).map_err(|error| ProfileError::Io {
        path: path.to_owned(),
        error: error.to_string(),
    })?;
    serde_json::from_str(&text).map_err(|error| ProfileError::Json {
        path: path.to_owned(),
        error: error.to_string(),
    })
}

fn strings(value: Option<&Value>) -> Option<BTreeSet<String>> {
    value?
        .as_array()?
        .iter()
        .map(|item| item.as_str().map(str::to_owned))
        .collect()
}

fn non_empty(value: Option<&Value>) -> bool {
    value.and_then(Value::as_str).is_some_and(|s| !s.is_empty())
}

/// Validate a fixture against a declarative profile without knowing the
/// profile's narrative vocabulary in Rust.
pub fn validate_declared_profile(profile: &Value, fixture: &Value) -> Result<(), ProfileError> {
    let mut errors = Vec::new();
    let profile_id = profile.pointer("/profile/id").and_then(Value::as_str);
    let profile_version = profile.pointer("/profile/version").and_then(Value::as_str);
    if fixture.pointer("/profile/id").and_then(Value::as_str) != profile_id
        || fixture.pointer("/profile/version").and_then(Value::as_str) != profile_version
    {
        errors.push("fixture profile identity/version does not match its profile".into());
    }

    let vocabulary = strings(profile.get("vocabulary")).unwrap_or_default();
    let used = strings(fixture.get("uses")).unwrap_or_default();
    for missing in vocabulary.difference(&used) {
        errors.push(format!(
            "fixture does not use declared vocabulary `{missing}`"
        ));
    }
    for unknown in used.difference(&vocabulary) {
        errors.push(format!("fixture uses undeclared vocabulary `{unknown}`"));
    }

    let required = strings(profile.get("required_semantics")).unwrap_or_default();
    let demonstrated = strings(fixture.get("demonstrates")).unwrap_or_default();
    for missing in required.difference(&demonstrated) {
        errors.push(format!("fixture does not demonstrate `{missing}`"));
    }

    let Some(entities) = fixture.get("entities").and_then(Value::as_array) else {
        errors.push("fixture.entities must be an array".into());
        return Err(ProfileError::Invalid(errors));
    };
    let mut ids = BTreeSet::new();
    for (index, entity) in entities.iter().enumerate() {
        let Some(id) = entity.get("id").and_then(Value::as_str) else {
            errors.push(format!("entities[{index}] has no id"));
            continue;
        };
        if !ids.insert(id.to_owned()) {
            errors.push(format!("duplicate entity id `{id}`"));
        }
        if !non_empty(entity.get("kind")) {
            errors.push(format!("entity `{id}` has no kind"));
        }
    }

    let Some(interactions) = fixture.get("interactions").and_then(Value::as_array) else {
        errors.push("fixture.interactions must be an array".into());
        return Err(ProfileError::Invalid(errors));
    };
    for (index, interaction) in interactions.iter().enumerate() {
        if !non_empty(interaction.get("rule")) {
            errors.push(format!("interactions[{index}] has no rule"));
        }
        if let Some(participants) = strings(interaction.get("participants")) {
            for participant in participants.difference(&ids) {
                errors.push(format!(
                    "interactions[{index}] references unknown entity `{participant}`"
                ));
            }
        } else {
            errors.push(format!("interactions[{index}] needs participants"));
        }
    }

    let completion = fixture.get("completion").and_then(Value::as_object);
    if completion
        .and_then(|value| value.get("mode"))
        .and_then(Value::as_str)
        != Some("cooperative")
    {
        errors.push("fixture completion must be cooperative".into());
    }
    if completion
        .and_then(|value| value.get("requires"))
        .and_then(Value::as_array)
        .is_none_or(Vec::is_empty)
    {
        errors.push("fixture completion must have at least one requirement".into());
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(ProfileError::Invalid(errors))
    }
}

/// Compile an IDApTIK UMS source into the game-owned v1 package envelope.
///
/// `idaptik_root` is explicit so the compiler consumes the sibling game's
/// versioned artifacts. Nothing is copied into UMS.
pub fn compile_idaptik(source_path: &Path, idaptik_root: &Path) -> Result<Value, ProfileError> {
    let source = read_json(source_path)?;
    let contract_rel = source
        .pointer("/contract/metadata_path")
        .and_then(Value::as_str)
        .ok_or_else(|| ProfileError::Invalid(vec!["contract.metadata_path is required".into()]))?;
    let scenario_rel = source
        .pointer("/contract/scenario_path")
        .and_then(Value::as_str)
        .ok_or_else(|| ProfileError::Invalid(vec!["contract.scenario_path is required".into()]))?;
    let contract = read_json(&idaptik_root.join(contract_rel))?;
    let scenario = read_json(&idaptik_root.join(scenario_rel))?;

    let mut errors = Vec::new();
    for (source_pointer, contract_field) in [
        ("/contract/id", "contract_id"),
        ("/contract/version", "contract_version"),
    ] {
        if source.pointer(source_pointer) != contract.get(contract_field) {
            errors.push(format!(
                "{source_pointer} does not match game contract `{contract_field}`"
            ));
        }
    }
    if source.pointer("/profile/id").and_then(Value::as_str)
        != contract.get("profile_id").and_then(Value::as_str)
        || source.pointer("/profile/version").and_then(Value::as_str) != Some("1.0.0")
    {
        errors.push("IDApTIK profile identity/version is incompatible".into());
    }
    if source.pointer("/package/scenario_id") != scenario.get("scenario_id") {
        errors.push("package scenario_id does not match authoritative scenario".into());
    }
    if scenario.get("format") != contract.get("scenario_format") {
        errors.push("authoritative scenario format does not match contract".into());
    }

    let declared_terms = strings(contract.get("taxonomy_terms")).unwrap_or_default();
    let supplied_terms: BTreeSet<String> = source
        .pointer("/package/taxonomy")
        .and_then(Value::as_object)
        .map(|map| map.keys().cloned().collect())
        .unwrap_or_default();
    if declared_terms != supplied_terms {
        errors.push(format!(
            "taxonomy keys differ from game contract: expected {declared_terms:?}, got {supplied_terms:?}"
        ));
    }

    for field in ["rooms", "doors", "cameras", "objectives"] {
        if scenario
            .get(field)
            .and_then(Value::as_array)
            .is_none_or(Vec::is_empty)
        {
            errors.push(format!("authoritative scenario has no {field}"));
        }
    }
    if scenario.get("props").and_then(Value::as_object).is_none() {
        errors.push("authoritative scenario has no props object".into());
    }
    if source
        .pointer("/package/actors")
        .and_then(Value::as_array)
        .is_none_or(|actors| actors.len() < 2)
    {
        errors.push("package needs a security and non-security actor".into());
    }

    if !errors.is_empty() {
        return Err(ProfileError::Invalid(errors));
    }

    let package = source
        .get("package")
        .and_then(Value::as_object)
        .ok_or_else(|| ProfileError::Invalid(vec!["package must be an object".into()]))?;
    let mut output: Map<String, Value> = package.clone();
    output.insert(
        "format".into(),
        contract
            .get("package_format")
            .cloned()
            .unwrap_or(Value::Null),
    );
    output.insert(
        "contract".into(),
        json!({
            "id": contract["contract_id"],
            "version": contract["contract_version"]
        }),
    );
    output.insert(
        "compatibility".into(),
        json!({
            "game": contract["game_id"],
            "game_version": "0.1.0",
            "profile": contract["profile_id"],
            "profile_version": source["profile"]["version"]
        }),
    );
    output.insert("scenario".into(), scenario);
    Ok(Value::Object(output))
}

pub fn write_pretty_json(path: &Path, value: &Value) -> Result<(), ProfileError> {
    let mut json = serde_json::to_string_pretty(value)
        .map_err(|error| ProfileError::Invalid(vec![error.to_string()]))?;
    json.push('\n');
    fs::write(path, json).map_err(|error| ProfileError::Io {
        path: path.to_owned(),
        error: error.to_string(),
    })
}

pub fn read_and_validate_declared_profile(
    profile_path: &Path,
    fixture_path: &Path,
) -> Result<(), ProfileError> {
    let profile = read_json(profile_path)?;
    let fixture = read_json(fixture_path)?;
    validate_declared_profile(&profile, &fixture)
}
