// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
//! Runtime reflection: the engine describes itself as data.
//!
//! This is what closes the generative loop. `config/verbs.ncl` generates
//! `vocab.rs`; [`describe`] reads the compiled registry back out as JSON; and
//! `just ai-edit-reflect` asserts the two are equal. The engine's
//! self-description and the source that generated it are then provably the
//! same object, rather than two things a human is asked to keep in step.
//!
//! It is also the honest way to answer "what can this engine do?" — the
//! answer is computed from the registry the engine actually dispatches on,
//! not from a doc comment that can rot.

use serde_json::{Map, Value, json};

use crate::constraints;
use crate::vocab::{self, VERBS};
use crate::{FRESH, GUARANTEES};

/// The engine's full self-description.
///
/// Shaped to match `nickel export config/verbs.ncl`'s derived views
/// (`names`, `arg_order`, `domains`) so the two can be compared directly.
pub fn describe() -> Value {
    let mut arg_order = Map::new();
    let mut domains = Map::new();
    let mut required = Map::new();
    let mut docs = Map::new();
    let mut collections = Map::new();

    for spec in VERBS.iter() {
        arg_order.insert(spec.name.into(), json!(spec.args));
        required.insert(spec.name.into(), json!(spec.required));
        docs.insert(spec.name.into(), json!(spec.doc));
        collections.insert(spec.name.into(), json!(spec.collection));

        let mut per_verb = Map::new();
        for (arg, domain) in spec.domains.iter() {
            per_verb.insert((*arg).into(), json!(domain));
        }
        domains.insert(spec.name.into(), Value::Object(per_verb));
    }

    json!({
        "names": VERBS.iter().map(|v| v.name).collect::<Vec<_>>(),
        "arg_order": arg_order,
        "required": required,
        "domains": domains,
        "docs": docs,
        "collections": collections,
        "vocabularies": vocabularies(),
        "constraints": constraints::NAMES,
        "guarantees": GUARANTEES,
        "fresh_placeholder": FRESH,
    })
}

/// Every closed world the engine enumerates over.
pub fn vocabularies() -> Value {
    json!({
        "device_kinds": vocab::DEVICE_KINDS,
        "guard_ranks": vocab::GUARD_RANKS,
        "dog_breeds": vocab::DOG_BREEDS,
        "drone_archetypes": vocab::DRONE_ARCHETYPES,
        "wiring_types": vocab::WIRING_TYPES,
        "npc_roles": vocab::NPC_ROLES,
        "character_archetypes": vocab::CHARACTER_ARCHETYPES,
        "character_modifiers": vocab::CHARACTER_MODIFIERS,
        "item_categories": vocab::ITEM_CATEGORIES,
        "zone_segments": vocab::ZONE_SEGMENTS,
    })
}
