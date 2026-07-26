// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
//! The edit verbs as state-in/state-out relations.
//!
//! Each verb relates an immutable level state to its successor. States are
//! never mutated: the output state is a fresh map sharing unchanged values, so
//! edit history is replayable and every intermediate state stays addressable.
//!
//! The verb surface matches the archive editor's C ABI (`add_zone`,
//! `add_device`, `add_guard`, `add_dog`, `add_drone`, `set_mission`,
//! `set_physical`); `create_level` is [`initial_state`], and (de)serialisation
//! is plain JSON handled by the script loader. UMS adds `add_npc`,
//! `add_character` and `add_item` so AI edits act directly on characters,
//! objects and NPCs rather than only on devices and security actors.
//!
//! There are no per-verb functions. [`apply`] is driven by the generated
//! registry in [`crate::vocab`], so a verb exists in exactly one place —
//! `config/verbs.ncl`.

use std::collections::BTreeMap;

use crate::microkanren::{Goal, Term, conj, eq, fail, is_ground, project};
use crate::vocab::{self, VerbSpec};

/// Keys of the level object graph: the archive editor's `LevelData`, plus the
/// UMS-owned `npcs` and `characters` collections for direct actor edits.
pub const LEVEL_KEYS: [&str; 17] = [
    "zones",
    "devices",
    "guards",
    "dogs",
    "drones",
    "assassins",
    "items",
    "npcs",
    "characters",
    "wiring",
    "zoneTransitions",
    "deviceDefences",
    "mission",
    "physical",
    "hasPBX",
    "pbxIp",
    "pbxWorldX",
];

/// Fields of `set_physical`'s block that are lifted to the top level of the
/// object graph (as in the archive `LevelData`) so the PBX consistency proof
/// can see them.
const PBX_KEYS: [&str; 3] = ["hasPBX", "pbxIp", "pbxWorldX"];

/// An empty level: the archive's `create_level`.
pub fn initial_state() -> Term {
    let mut m = BTreeMap::new();
    for key in [
        "zones",
        "devices",
        "guards",
        "dogs",
        "drones",
        "assassins",
        "items",
        "npcs",
        "characters",
        "wiring",
        "zoneTransitions",
        "deviceDefences",
    ] {
        m.insert(key.to_string(), Term::Seq(Vec::new()));
    }
    m.insert("mission".into(), Term::Null);
    m.insert("physical".into(), Term::Null);
    m.insert("hasPBX".into(), Term::Bool(false));
    m.insert("pbxIp".into(), Term::Null);
    m.insert("pbxWorldX".into(), Term::Null);
    Term::Map(m)
}

/// Goal: `s_out` is `s_in` with `record` appended to `s_in[key]`.
///
/// Fails — rather than erring — when the state or the record is not yet
/// ground. Ground them first with a domain relation; a verb whose record is
/// still non-ground must not embed logic variables into a state.
fn append(s_in: Term, s_out: Term, key: &'static str, record: Term) -> Goal {
    project(vec![s_in, record], move |resolved| {
        let (state, rec) = (&resolved[0], &resolved[1]);
        if !is_ground(state) || !is_ground(rec) {
            return fail();
        }
        let Some(map) = state.as_map() else {
            return fail();
        };
        let Some(existing) = map.get(key).and_then(|t| t.as_seq()) else {
            return fail();
        };
        let mut next = map.clone();
        let mut items = existing.clone();
        items.push(rec.clone());
        next.insert(key.to_string(), Term::Seq(items));
        eq(s_out.clone(), Term::Map(next))
    })
}

/// Goal: `s_out` is `s_in` with `field` set to `value`.
fn set_field(s_in: Term, s_out: Term, field: &'static str, value: Term) -> Goal {
    project(vec![s_in, value], move |resolved| {
        let (state, block) = (&resolved[0], &resolved[1]);
        if !is_ground(state) || !is_ground(block) {
            return fail();
        }
        let Some(map) = state.as_map() else {
            return fail();
        };
        let mut next = map.clone();
        next.insert(field.to_string(), block.clone());

        // set_physical lifts the PBX triple to the top level so the PBX
        // consistency proof can see it.
        if field == "physical" {
            let Some(b) = block.as_map() else {
                return fail();
            };
            for key in PBX_KEYS {
                if let Some(v) = b.get(key) {
                    next.insert(key.to_string(), v.clone());
                }
            }
        }
        eq(s_out.clone(), Term::Map(next))
    })
}

/// Apply a verb relationally: `s_out` is `s_in` after `spec` with `args`.
///
/// `args` are positional, in `spec.args` order. Every argument that ranges
/// over a closed world is conjoined with its domain relation *before* the
/// state is built, which is what makes an out-of-vocabulary value
/// ungeneratable rather than merely detectable after the fact.
pub fn apply(spec: &'static VerbSpec, s_in: Term, args: &[Term], s_out: Term) -> Goal {
    let mut goals: Vec<Goal> = Vec::new();

    // Domain relations first: narrow before building.
    //
    // An *absent* optional argument (Null, e.g. add_zone's `segment`) carries
    // no domain obligation — constraining it would demand that "no segment"
    // be a member of ZONE_SEGMENTS, which fails and would make every
    // segment-less add_zone unsatisfiable.
    for (name, value) in spec.args.iter().zip(args.iter()) {
        if matches!(value, Term::Null) && !spec.required.contains(name) {
            continue;
        }
        if let Some(domain) = spec.domain(name) {
            goals.push(vocab::in_domain(value.clone(), domain));
        }
    }

    match spec.name {
        "set_mission" | "set_physical" => {
            goals.push(set_field(
                s_in,
                s_out,
                if spec.name == "set_mission" {
                    "mission"
                } else {
                    "physical"
                },
                args[0].clone(),
            ));
        }
        _ => {
            // Build the record from the verb's declared argument names. An
            // absent optional argument (Term::Null for `segment`) is omitted
            // so it never reaches the wire as an explicit null.
            let mut record = BTreeMap::new();
            for (name, value) in spec.args.iter().zip(args.iter()) {
                if matches!(value, Term::Null) && !spec.required.contains(name) {
                    continue;
                }
                record.insert((*name).to_string(), value.clone());
            }
            goals.push(append(s_in, s_out, spec.collection, Term::Map(record)));
        }
    }

    conj(goals)
}
