// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
//! `schemas/taxonomy-map.json` — the UMS ↔ game taxonomy seam.
//!
//! The map is load-bearing: it declares how UMS device kinds and zone tiers
//! ground to the game's own enums, so an incoherent map must fail loudly
//! rather than silently loosening edit-script validation.
//!
//! Per ADR-0002 the game enum was extended to a superset of the UMS enum, so
//! the device half is a total 1:1 identity — kept as an explicit table
//! precisely so drift on either side is caught here. The zone half was
//! ratified 2026-07-21: the tier-band ladder stands, `Iot`/`Isp`/`Service`
//! stay override-only, and an authored per-zone `segment` always wins.

use std::collections::BTreeSet;

use serde_json::Value;

/// Check the map's internal coherence, returning every problem found.
pub fn check(doc: &Value) -> Vec<String> {
    let mut errors = Vec::new();

    match doc.get("format").and_then(|f| f.as_str()) {
        Some(f)
            if f.strip_prefix("idaptik-taxonomy-map/")
                .is_some_and(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit())) => {}
        _ => errors.push("format must match idaptik-taxonomy-map/<n>".into()),
    }

    // device-kinds: a non-empty string->string map.
    let kinds = doc.get("device-kinds").and_then(|k| k.as_object());
    let kinds = match kinds {
        Some(k) if !k.is_empty() && k.values().all(|v| v.is_string()) => k.clone(),
        _ => {
            errors.push("device-kinds must map UMS kind names to game kind names".into());
            serde_json::Map::new()
        }
    };

    // game-device-kinds: a non-repeating array of strings.
    let game_kinds: Vec<String> = match doc.get("game-device-kinds").and_then(|g| g.as_array()) {
        Some(a) if !a.is_empty() && a.iter().all(|v| v.is_string()) => {
            let v: Vec<String> = a
                .iter()
                .map(|s| s.as_str().unwrap_or_default().to_string())
                .collect();
            let distinct: BTreeSet<&String> = v.iter().collect();
            if distinct.len() != v.len() {
                errors.push("game-device-kinds must be a non-repeating array of strings".into());
                Vec::new()
            } else {
                v
            }
        }
        _ => {
            errors.push("game-device-kinds must be a non-repeating array of strings".into());
            Vec::new()
        }
    };

    let targets: Vec<&str> = kinds.values().filter_map(|v| v.as_str()).collect();
    if !game_kinds.is_empty() {
        let known: BTreeSet<&str> = game_kinds.iter().map(|s| s.as_str()).collect();
        let unmapped: BTreeSet<&&str> = targets.iter().filter(|t| !known.contains(**t)).collect();
        if !unmapped.is_empty() {
            let mut u: Vec<&str> = unmapped.into_iter().copied().collect();
            u.sort_unstable();
            errors.push(format!(
                "device-kinds targets not in game-device-kinds: {u:?}"
            ));
        }
    }
    let distinct_targets: BTreeSet<&&str> = targets.iter().collect();
    if distinct_targets.len() != kinds.len() {
        errors.push("device-kinds must be 1:1 (no two UMS kinds may share a game kind)".into());
    }

    // zone-segments: a non-repeating array of strings.
    let segments: Vec<String> = match doc.get("zone-segments").and_then(|s| s.as_array()) {
        Some(a) if !a.is_empty() && a.iter().all(|v| v.is_string()) => {
            let v: Vec<String> = a
                .iter()
                .map(|s| s.as_str().unwrap_or_default().to_string())
                .collect();
            let distinct: BTreeSet<&String> = v.iter().collect();
            if distinct.len() != v.len() {
                errors.push("zone-segments must be a non-repeating array of strings".into());
                Vec::new()
            } else {
                v
            }
        }
        _ => {
            errors.push("zone-segments must be a non-repeating array of strings".into());
            Vec::new()
        }
    };

    // zone-tier-bands: must start at 0 so every tier resolves, and strictly
    // increase so the "highest min-tier <= tier wins" rule is unambiguous.
    let bands = match doc.get("zone-tier-bands").and_then(|b| b.as_array()) {
        Some(a) if !a.is_empty() => a.clone(),
        _ => {
            errors.push("zone-tier-bands must be a non-empty array".into());
            Vec::new()
        }
    };

    let mut last_tier: Option<i64> = None;
    for (i, band) in bands.iter().enumerate() {
        let obj = band.as_object();
        let has_exact_keys = obj.is_some_and(|o| {
            o.len() == 2 && o.contains_key("min-tier") && o.contains_key("segment")
        });
        let tier = band.get("min-tier").and_then(|t| t.as_i64());
        let segment = band.get("segment").and_then(|s| s.as_str());

        if !has_exact_keys || tier.is_none_or(|t| t < 0) {
            errors.push(format!(
                "zone-tier-bands[{i}] must be {{min-tier >= 0, segment}}"
            ));
            continue;
        }
        let tier = tier.expect("checked above");

        if !segments.is_empty() && !segment.is_some_and(|s| segments.iter().any(|x| x == s)) {
            errors.push(format!(
                "zone-tier-bands[{i}].segment must be one of {segments:?}"
            ));
        }
        if i == 0 && tier != 0 {
            errors.push("zone-tier-bands must start at min-tier 0 so every tier resolves".into());
        }
        if last_tier.is_some_and(|lt| tier <= lt) {
            errors.push("zone-tier-bands min-tiers must be strictly increasing".into());
        }
        last_tier = Some(tier);
    }

    errors
}
