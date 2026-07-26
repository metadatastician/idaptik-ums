// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
//! The cross-domain validity proofs, as relational goals.
//!
//! These re-express the archive editor's Idris2 proofs (`GuardsInZones`,
//! `DefenceTargets`, `ZonesOrdered`, `PBXConsistent`, `DevicesExist`) plus
//! `ItemsInZones` for the UMS object collection, as goals over a state term.
//!
//! An AI-proposed edit is only emitted if a model satisfying *all* of them
//! exists for the resulting state. Constraint checking is part of the same
//! search that generates the edit, not a post-hoc filter — that is the whole
//! type-6 claim in ADR-0001.
//!
//! Each constraint takes a state term (possibly a logic variable bound during
//! the search) and fails on non-ground states, so goal ordering stays safe.

use crate::microkanren::{Goal, Term, conj, fail, is_ground, membero, project, succeed};
use crate::vocab;

/// Lift a function over a *ground* state into a goal.
fn over_state(state: Term, f: impl Fn(&Term) -> Goal + 'static) -> Goal {
    project(vec![state], move |resolved| {
        let st = &resolved[0];
        if !is_ground(st) || st.as_map().is_none() {
            return fail();
        }
        f(st)
    })
}

/// Ids of a named collection, as terms.
fn ids(st: &Term, collection: &str) -> Vec<Term> {
    st.get(collection)
        .and_then(|t| t.as_seq())
        .map(|items| {
            items
                .iter()
                .filter_map(|i| i.get("id").cloned())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

/// Members of a collection, or an empty slice when absent.
fn members<'a>(st: &'a Term, collection: &str) -> &'a [Term] {
    st.get(collection)
        .and_then(|t| t.as_seq())
        .map(|v| v.as_slice())
        .unwrap_or(&[])
}

/// `GuardsInZones`: every mobile actor — security actors (guard, dog, drone,
/// assassin) and inhabitants (NPCs, named characters) — stands in a declared
/// zone.
pub fn guards_in_zones(state: Term) -> Goal {
    over_state(state, |st| {
        let zone_ids = ids(st, "zones");
        let mut goals = Vec::new();
        for collection in [
            "guards",
            "dogs",
            "drones",
            "assassins",
            "npcs",
            "characters",
        ] {
            for actor in members(st, collection) {
                match actor.get("zone") {
                    Some(z) => goals.push(membero(z.clone(), &zone_ids)),
                    None => return fail(),
                }
            }
        }
        conj(goals)
    })
}

/// `DefenceTargets`: every device defence targets an existing device.
pub fn defence_targets_exist(state: Term) -> Goal {
    over_state(state, |st| {
        let device_ids = ids(st, "devices");
        let mut goals = Vec::new();
        for defence in members(st, "deviceDefences") {
            match defence.get("target") {
                Some(t) => goals.push(membero(t.clone(), &device_ids)),
                None => return fail(),
            }
        }
        conj(goals)
    })
}

/// `ZonesOrdered`: zone worldX intervals are well-formed and disjoint, and
/// security tiers do not decrease as worldX increases (deeper into the
/// building means at least as hardened).
///
/// This is the decidable, pointer-free half of the constraint set, and the
/// one mirrored by the SPARK/GNATprove reference model in `spark/`. The two
/// are pinned together by a parity test so they cannot silently diverge.
pub fn zones_ordered(state: Term) -> Goal {
    over_state(state, |st| {
        let zones = members(st, "zones");
        let mut ordered: Vec<&Term> = zones.iter().collect();
        ordered.sort_by(|a, b| {
            let ax = a.get("worldXStart").and_then(|t| t.as_f64()).unwrap_or(0.0);
            let bx = b.get("worldXStart").and_then(|t| t.as_f64()).unwrap_or(0.0);
            ax.partial_cmp(&bx).unwrap_or(std::cmp::Ordering::Equal)
        });

        let mut previous_end: Option<f64> = None;
        let mut previous_tier: Option<f64> = None;
        for zone in ordered {
            let (Some(start), Some(end), Some(tier)) = (
                zone.get("worldXStart").and_then(|t| t.as_f64()),
                zone.get("worldXEnd").and_then(|t| t.as_f64()),
                zone.get("securityTier").and_then(|t| t.as_f64()),
            ) else {
                return fail();
            };
            if start > end {
                return fail();
            }
            if previous_end.is_some_and(|pe| start < pe) {
                return fail();
            }
            if previous_tier.is_some_and(|pt| tier < pt) {
                return fail();
            }
            previous_end = Some(end);
            previous_tier = Some(tier);
        }
        succeed()
    })
}

/// `PBXConsistent`: `hasPBX` implies a PBX IP, a PBX worldX position and a
/// `PhoneSystem` device; no PBX implies no dangling PBX fields.
pub fn pbx_consistent(state: Term) -> Goal {
    over_state(state, |st| {
        let has_pbx = st.get("hasPBX").map(|t| t.is_truthy()).unwrap_or(false);
        if has_pbx {
            let has_ip = st
                .get("pbxIp")
                .and_then(|t| t.as_str())
                .is_some_and(|s| !s.is_empty());
            let has_position = st
                .get("pbxWorldX")
                .is_some_and(|t| !matches!(t, Term::Null));
            let has_phone_system = members(st, "devices")
                .iter()
                .any(|d| d.get("kind").and_then(|k| k.as_str()) == Some("PhoneSystem"));
            if has_ip && has_position && has_phone_system {
                succeed()
            } else {
                fail()
            }
        } else {
            let dangling = st.get("pbxIp").is_some_and(|t| !matches!(t, Term::Null))
                || st
                    .get("pbxWorldX")
                    .is_some_and(|t| !matches!(t, Term::Null));
            if dangling { fail() } else { succeed() }
        }
    })
}

/// `DevicesExist`: every device sits in a declared zone, and every wiring run
/// has a known `WiringType` and connects existing devices.
pub fn devices_exist(state: Term) -> Goal {
    over_state(state, |st| {
        let zone_ids = ids(st, "zones");
        let device_ids = ids(st, "devices");
        let mut goals = Vec::new();

        for device in members(st, "devices") {
            match device.get("zone") {
                Some(z) => goals.push(membero(z.clone(), &zone_ids)),
                None => return fail(),
            }
        }
        for run in members(st, "wiring") {
            if run.as_map().is_none() {
                return fail();
            }
            let ty = run.get("type").cloned().unwrap_or(Term::Null);
            goals.push(vocab::in_domain(ty, &vocab::WIRING_TYPES));
            goals.push(membero(
                run.get("from").cloned().unwrap_or(Term::Null),
                &device_ids,
            ));
            goals.push(membero(
                run.get("to").cloned().unwrap_or(Term::Null),
                &device_ids,
            ));
        }
        conj(goals)
    })
}

/// `ItemsInZones`: every placed object/item sits in a declared zone — no
/// orphaned loot floating outside the level geometry.
pub fn items_in_zones(state: Term) -> Goal {
    over_state(state, |st| {
        let zone_ids = ids(st, "zones");
        let mut goals = Vec::new();
        for item in members(st, "items") {
            match item.get("zone") {
                Some(z) => goals.push(membero(z.clone(), &zone_ids)),
                None => return fail(),
            }
        }
        conj(goals)
    })
}

/// The six proofs, in the order the engine's report lists them.
pub const NAMES: [&str; 6] = [
    "guards-in-zones",
    "defence-targets",
    "zones-ordered",
    "pbx-consistent",
    "devices-exist",
    "items-in-zones",
];

/// Goal: the state satisfies all six validity proofs.
pub fn all_constraints(state: Term) -> Goal {
    conj(vec![
        guards_in_zones(state.clone()),
        defence_targets_exist(state.clone()),
        zones_ordered(state.clone()),
        pbx_consistent(state.clone()),
        devices_exist(state.clone()),
        items_in_zones(state),
    ])
}
