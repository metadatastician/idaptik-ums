// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// game_systems.zig -- FFI operations for runtime game systems.
// Author: Jonathan D.A. Jewell
//
// Companion to GameSystems.idr.  Provides C-ABI types and functions for:
//   - Combat: damage calculation, HP management, critical roll resolution
//   - Detection: alert score accumulation, detection event processing
//   - Skills: attribute-based skill check resolution
//   - Equipment: loadout slot validation, deck capacity checks

const std = @import("std");

// =========================================================================
// Types (mirrors GameSystems.idr)
// =========================================================================

pub const DamageType = enum(u8) {
    physical = 0,
    electric = 1,
    cyber = 2,
    fall = 3,
};

pub const CriticalOutcome = enum(u8) {
    critical_failure = 0,
    normal_result = 1,
    critical_success = 2,
    perfect_execution = 3,
};

pub const DetectionSource = enum(u8) {
    camera = 0,
    guard = 1,
    dog = 2,
    drone = 3,
    alarm = 4,
    noise = 5,
    cyber_trace = 6,
};

pub const JessicaSubclass = enum(u8) {
    assault = 0,
    recon = 1,
    engineer = 2,
    signals = 3,
    medic = 4,
    logistics = 5,
};

pub const QCertification = enum(u8) {
    network_exploit = 0,
    crypto_analysis = 1,
    social_eng = 2,
    forensic_analysis = 3,
    malware_design = 4,
    counter_intel = 5,
};

pub const LoadoutSlot = enum(u8) {
    weapon = 0,
    tool = 1,
    consumable = 2,
};

pub const Attribute = enum(u8) {
    str = 0,
    dex = 1,
    int = 2,
    con = 3,
    wil = 4,
    cha = 5,
};

pub const DetectionEvent = extern struct {
    source: DetectionSource,
    _pad0: u8 = 0,
    _pad1: u8 = 0,
    _pad2: u8 = 0,
    severity: u32,
    timestamp: f64,
};

/// Player state for combat and skill checks.
pub const PlayerState = extern struct {
    hp: u32,
    max_hp: u32,
    armour: u32,
    subclass: JessicaSubclass,
    _pad0: u8 = 0,
    _pad1: u8 = 0,
    _pad2: u8 = 0,
    /// Attribute scores (6 attributes, STR through CHA).
    attributes: [6]u8,
    _pad3: u8 = 0,
    _pad4: u8 = 0,
    /// Current alert score (0-100).
    alert_score: u32,
};

// =========================================================================
// Combat functions
// =========================================================================

/// Apply damage to a player, respecting armour.
///
/// Damage formula: effective = max(0, raw_damage - armour)
/// HP floors at 0 (never goes negative, mirrors Idris2 Nat).
/// Returns the new HP value.
pub export fn idaptik_gs_apply_damage(
    state: ?*PlayerState,
    raw_damage: u32,
    damage_type: u8,
) callconv(.c) u32 {
    const s = state orelse return 0;

    // Cyber damage bypasses physical armour.
    const effective_armour = if (damage_type == @intFromEnum(DamageType.cyber))
        @as(u32, 0)
    else
        s.armour;

    const effective_damage = if (raw_damage > effective_armour)
        raw_damage - effective_armour
    else
        0;

    if (effective_damage >= s.hp) {
        s.hp = 0;
    } else {
        s.hp -= effective_damage;
    }
    return s.hp;
}

/// Heal a player, capped at max_hp.
/// Returns the new HP value.
pub export fn idaptik_gs_heal(
    state: ?*PlayerState,
    amount: u32,
) callconv(.c) u32 {
    const s = state orelse return 0;
    const new_hp = @as(u64, s.hp) + @as(u64, amount);
    s.hp = if (new_hp > s.max_hp) s.max_hp else @intCast(new_hp);
    return s.hp;
}

/// Check if a player is alive (HP > 0).
pub export fn idaptik_gs_is_alive(
    state: ?*const PlayerState,
) callconv(.c) bool {
    const s = state orelse return false;
    return s.hp > 0;
}

// =========================================================================
// Critical roll resolution
// =========================================================================

/// Resolve a critical roll based on attribute score and roll value.
///
/// The roll value is 0-99 (d100).  Thresholds:
///   - Roll < 5:                     CriticalFailure (always 5% chance)
///   - Roll < attribute_score:       CriticalSuccess
///   - Roll < attribute_score + 10:  NormalResult (success)
///   - Roll >= 95:                   PerfectExecution (top 5%)
///   - Otherwise:                    NormalResult (failure, but not critical)
///
/// This mirrors the Idris2 CriticalOutcome type's probability partition.
pub export fn idaptik_gs_resolve_critical(
    attribute_score: u8,
    roll: u8,
) callconv(.c) u8 {
    if (roll < 5) return @intFromEnum(CriticalOutcome.critical_failure);
    if (roll >= 95) return @intFromEnum(CriticalOutcome.perfect_execution);
    if (roll < attribute_score) return @intFromEnum(CriticalOutcome.critical_success);
    return @intFromEnum(CriticalOutcome.normal_result);
}

// =========================================================================
// Detection system
// =========================================================================

/// Accumulate a detection event into the player's alert score.
///
/// The alert score is clamped to 0-100.  Returns the new score.
pub export fn idaptik_gs_add_detection(
    state: ?*PlayerState,
    event: ?*const DetectionEvent,
) callconv(.c) u32 {
    const s = state orelse return 0;
    const ev = event orelse return s.alert_score;

    const new_score = @as(u64, s.alert_score) + @as(u64, ev.severity);
    s.alert_score = if (new_score > 100) 100 else @intCast(new_score);
    return s.alert_score;
}

/// Get the alert level string index from the current score.
///
/// Returns: 0=green (0-24), 1=yellow (25-49), 2=orange (50-74), 3=red (75-100).
pub export fn idaptik_gs_alert_level_from_score(
    score: u32,
) callconv(.c) u8 {
    if (score >= 75) return 3; // red
    if (score >= 50) return 2; // orange
    if (score >= 25) return 1; // yellow
    return 0; // green
}

// =========================================================================
// Skill checks
// =========================================================================

/// Perform an attribute-based skill check.
///
/// Compares the player's attribute score against a difficulty threshold.
/// Returns the CriticalOutcome as a u8.
///
/// Uses the critical roll system with the relevant attribute as the
/// base score. The `roll` parameter should be a random d100 value.
pub export fn idaptik_gs_skill_check(
    state: ?*const PlayerState,
    attribute_idx: u8,
    difficulty: u8,
    roll: u8,
) callconv(.c) u8 {
    const s = state orelse return @intFromEnum(CriticalOutcome.critical_failure);
    if (attribute_idx >= 6) return @intFromEnum(CriticalOutcome.critical_failure);

    // Effective score = attribute - difficulty (floored at 0).
    const attr = s.attributes[attribute_idx];
    const effective = if (attr > difficulty) attr - difficulty else 0;

    return idaptik_gs_resolve_critical(effective, roll);
}

/// Check if a subclass bonus applies to a given skill check context.
///
/// Returns a bonus modifier (0-20) based on subclass and context.
/// Contexts: 0=combat, 1=stealth, 2=tech, 3=comms, 4=medical, 5=logistics.
pub export fn idaptik_gs_subclass_bonus(
    subclass: u8,
    context: u8,
) callconv(.c) u8 {
    // Subclass matches context → +15 bonus.
    // Adjacent context → +5 bonus.
    // Otherwise → 0.
    if (subclass == context) return 15;
    if (subclass > 0 and subclass - 1 == context) return 5;
    if (subclass < 5 and subclass + 1 == context) return 5;
    return 0;
}

// =========================================================================
// Equipment validation
// =========================================================================

/// Validate a loadout slot assignment (each slot can hold exactly one item).
/// Returns true if the slot value is valid (0-2).
pub export fn idaptik_gs_valid_loadout_slot(slot: u8) callconv(.c) bool {
    return slot <= 2;
}

/// Validate Q's program deck capacity.
/// Returns true if the count is within bounds (0-4).
pub export fn idaptik_gs_valid_deck_capacity(count: u8) callconv(.c) bool {
    return count <= 4;
}

// =========================================================================
// Tests
// =========================================================================

test "damage respects armour" {
    var state = PlayerState{
        .hp = 100,
        .max_hp = 100,
        .armour = 10,
        .subclass = .assault,
        .attributes = .{ 50, 50, 50, 50, 50, 50 },
        .alert_score = 0,
    };

    // 20 physical damage - 10 armour = 10 effective.
    try std.testing.expectEqual(@as(u32, 90), idaptik_gs_apply_damage(&state, 20, 0));

    // 5 physical damage - 10 armour = 0 effective.
    try std.testing.expectEqual(@as(u32, 90), idaptik_gs_apply_damage(&state, 5, 0));

    // Cyber damage bypasses armour.
    try std.testing.expectEqual(@as(u32, 70), idaptik_gs_apply_damage(&state, 20, 2));
}

test "HP never goes negative" {
    var state = PlayerState{
        .hp = 10,
        .max_hp = 100,
        .armour = 0,
        .subclass = .recon,
        .attributes = .{ 50, 50, 50, 50, 50, 50 },
        .alert_score = 0,
    };

    try std.testing.expectEqual(@as(u32, 0), idaptik_gs_apply_damage(&state, 999, 0));
    try std.testing.expect(!idaptik_gs_is_alive(&state));
}

test "heal caps at max HP" {
    var state = PlayerState{
        .hp = 90,
        .max_hp = 100,
        .armour = 0,
        .subclass = .medic,
        .attributes = .{ 50, 50, 50, 50, 50, 50 },
        .alert_score = 0,
    };

    try std.testing.expectEqual(@as(u32, 100), idaptik_gs_heal(&state, 50));
}

test "critical roll resolution" {
    // Roll 3 → critical failure (< 5).
    try std.testing.expectEqual(@as(u8, 0), idaptik_gs_resolve_critical(50, 3));
    // Roll 97 → perfect execution (>= 95).
    try std.testing.expectEqual(@as(u8, 3), idaptik_gs_resolve_critical(50, 97));
    // Roll 30 with attribute 50 → critical success (30 < 50).
    try std.testing.expectEqual(@as(u8, 2), idaptik_gs_resolve_critical(50, 30));
    // Roll 60 with attribute 50 → normal (60 >= 50).
    try std.testing.expectEqual(@as(u8, 1), idaptik_gs_resolve_critical(50, 60));
}

test "detection accumulation" {
    var state = PlayerState{
        .hp = 100,
        .max_hp = 100,
        .armour = 0,
        .subclass = .recon,
        .attributes = .{ 50, 50, 50, 50, 50, 50 },
        .alert_score = 0,
    };

    const camera_event = DetectionEvent{
        .source = .camera,
        .severity = 30,
        .timestamp = 0.0,
    };

    try std.testing.expectEqual(@as(u32, 30), idaptik_gs_add_detection(&state, &camera_event));
    try std.testing.expectEqual(@as(u8, 1), idaptik_gs_alert_level_from_score(30)); // yellow

    const guard_event = DetectionEvent{
        .source = .guard,
        .severity = 50,
        .timestamp = 1.0,
    };

    try std.testing.expectEqual(@as(u32, 80), idaptik_gs_add_detection(&state, &guard_event));
    try std.testing.expectEqual(@as(u8, 3), idaptik_gs_alert_level_from_score(80)); // red
}

test "subclass bonus" {
    // Assault (0) in combat context (0) → 15.
    try std.testing.expectEqual(@as(u8, 15), idaptik_gs_subclass_bonus(0, 0));
    // Assault (0) in stealth context (1) → 5 (adjacent).
    try std.testing.expectEqual(@as(u8, 5), idaptik_gs_subclass_bonus(0, 1));
    // Assault (0) in medical context (4) → 0 (not adjacent).
    try std.testing.expectEqual(@as(u8, 0), idaptik_gs_subclass_bonus(0, 4));
}
