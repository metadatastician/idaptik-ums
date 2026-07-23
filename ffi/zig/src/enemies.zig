// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// enemies.zig -- FFI operations for guards, dogs, drones, and assassins.
// Author: Jonathan D.A. Jewell
//
// Companion to Guards.idr, Dogs.idr, Drones.idr, Assassin.idr.
// Provides C-ABI functions for:
//   - Threat assessment (total enemy count, threat level per zone)
//   - Enemy queries by zone or position range
//   - Alert escalation helpers
//
// The basic add_guard/add_dog/add_drone exports live in main.zig.
// This module adds higher-level query and analysis operations.

const std = @import("std");
const types = @import("types");

// =========================================================================
// Threat assessment
// =========================================================================

/// Count total enemies (guards + dogs + drones + assassins) in the level.
pub export fn idaptik_ums_total_enemy_count(
    level: ?*const types.LevelData,
) callconv(.c) u32 {
    const lv = level orelse return 0;
    return lv.guards_len + lv.dogs_len + lv.drones_len + lv.assassins_len;
}

/// Compute a threat score for the level.
///
/// Threat scoring (matches the balance analyser weights):
///   - basic_guard: 1, enforcer: 2, anti_hacker: 3, sentinel: 4
///   - assassin: 5, elite_guard: 6, security_chief: 7, rival_hacker: 8
///   - patrol dog: 2, bloodhound: 3, robo_dog: 4
///   - helper drone: 1, hunter drone: 3, killer drone: 5
///   - assassin encounter: 6 per ambush wave
pub export fn idaptik_ums_threat_score(
    level: ?*const types.LevelData,
) callconv(.c) u32 {
    const lv = level orelse return 0;
    var score: u32 = 0;

    for (lv.guards[0..lv.guards_len]) |g| {
        score += @as(u32, @intFromEnum(g.rank)) + 1;
    }

    for (lv.dogs[0..lv.dogs_len]) |d| {
        score += switch (d.breed) {
            .patrol => @as(u32, 2),
            .bloodhound => 3,
            .robo_dog => 4,
        };
    }

    for (lv.drones[0..lv.drones_len]) |d| {
        score += switch (d.archetype) {
            .helper => @as(u32, 1),
            .hunter => 3,
            .killer => 5,
        };
    }

    for (lv.assassins[0..lv.assassins_len]) |a| {
        score += a.ambush_count * 6;
    }

    return score;
}

// =========================================================================
// Zone-based queries
// =========================================================================

/// Count guards in a specific zone (by name pointer).
///
/// Compares zone names using null-terminated string equality.
/// Returns 0 if the level or zone_name is null.
pub export fn idaptik_ums_guards_in_zone(
    level: ?*const types.LevelData,
    zone_name: ?[*:0]const u8,
) callconv(.c) u32 {
    const lv = level orelse return 0;
    const needle = std.mem.span(zone_name orelse return 0);
    var count: u32 = 0;
    for (lv.guards[0..lv.guards_len]) |g| {
        if (g.zone) |gz| {
            if (std.mem.eql(u8, needle, std.mem.span(gz))) count += 1;
        }
    }
    return count;
}

// =========================================================================
// Position-range queries
// =========================================================================

/// Count all enemies (guards + dogs + drones) within a horizontal range.
///
/// Useful for danger-zone highlighting in the level editor.
/// Assassins are excluded because they spawn dynamically.
pub export fn idaptik_ums_enemies_in_range(
    level: ?*const types.LevelData,
    x_min: f64,
    x_max: f64,
) callconv(.c) u32 {
    const lv = level orelse return 0;
    var count: u32 = 0;

    for (lv.guards[0..lv.guards_len]) |g| {
        if (g.world_x.position >= x_min and g.world_x.position <= x_max) count += 1;
    }
    for (lv.dogs[0..lv.dogs_len]) |d| {
        if (d.world_x.position >= x_min and d.world_x.position <= x_max) count += 1;
    }
    for (lv.drones[0..lv.drones_len]) |d| {
        if (d.world_x.position >= x_min and d.world_x.position <= x_max) count += 1;
    }

    return count;
}

// =========================================================================
// Highest-rank query
// =========================================================================

/// Return the highest guard rank present in the level.
///
/// Returns 255 (sentinel value) if no guards are placed.
/// Otherwise returns the enum discriminant of the highest rank.
pub export fn idaptik_ums_highest_guard_rank(
    level: ?*const types.LevelData,
) callconv(.c) u8 {
    const lv = level orelse return 255;
    if (lv.guards_len == 0) return 255;

    var max_rank: u8 = 0;
    for (lv.guards[0..lv.guards_len]) |g| {
        const rank = @intFromEnum(g.rank);
        if (rank > max_rank) max_rank = rank;
    }
    return max_rank;
}

// =========================================================================
// Add functions for device defences and zone transitions
// =========================================================================

/// Append a device defence configuration to the level.
///
/// Returns `true` on success, `false` if at capacity or null pointer.
pub export fn idaptik_ums_add_device_defence(
    level: ?*types.LevelData,
    defence: ?*const types.DeviceDefenceConfig,
) callconv(.c) bool {
    const lv = level orelse return false;
    const d = defence orelse return false;
    if (lv.device_defences_len >= types.MAX_DEVICE_DEFENCES) return false;
    lv.device_defences[lv.device_defences_len] = d.*;
    lv.device_defences_len += 1;
    return true;
}

/// Append a zone transition to the level.
///
/// Returns `true` on success, `false` if at capacity or null pointer.
pub export fn idaptik_ums_add_zone_transition(
    level: ?*types.LevelData,
    transition: ?*const types.ZoneTransition,
) callconv(.c) bool {
    const lv = level orelse return false;
    const t = transition orelse return false;
    if (lv.zone_transitions_len >= types.MAX_ZONE_TRANSITIONS) return false;
    lv.zone_transitions[lv.zone_transitions_len] = t.*;
    lv.zone_transitions_len += 1;
    return true;
}

// =========================================================================
// Tests
// =========================================================================

test "total enemy count" {
    var level = std.mem.zeroes(types.LevelData);
    level.guards_len = 3;
    level.dogs_len = 2;
    level.drones_len = 1;
    level.assassins_len = 1;
    try std.testing.expectEqual(@as(u32, 7), idaptik_ums_total_enemy_count(&level));
}

test "threat score calculation" {
    var level = std.mem.zeroes(types.LevelData);

    // One basic guard (rank 0 → score 1).
    level.guards[0] = .{
        .world_x = .{ .position = 100.0 },
        .zone = null,
        .rank = .basic_guard,
        .patrol_radius = 50.0,
    };
    level.guards_len = 1;

    // One robo dog (score 4).
    level.dogs[0] = .{
        .world_x = .{ .position = 200.0 },
        .breed = .robo_dog,
        .patrol_radius = 30.0,
    };
    level.dogs_len = 1;

    // One killer drone (score 5).
    level.drones[0] = .{
        .world_x = .{ .position = 300.0 },
        .archetype = .killer,
        .altitude = 100.0,
    };
    level.drones_len = 1;

    // 1 + 4 + 5 = 10.
    try std.testing.expectEqual(@as(u32, 10), idaptik_ums_threat_score(&level));
}

test "enemies in range" {
    var level = std.mem.zeroes(types.LevelData);

    level.guards[0] = .{
        .world_x = .{ .position = 50.0 },
        .zone = null,
        .rank = .basic_guard,
        .patrol_radius = 20.0,
    };
    level.guards[1] = .{
        .world_x = .{ .position = 200.0 },
        .zone = null,
        .rank = .enforcer,
        .patrol_radius = 30.0,
    };
    level.guards_len = 2;

    level.dogs[0] = .{
        .world_x = .{ .position = 75.0 },
        .breed = .patrol,
        .patrol_radius = 10.0,
    };
    level.dogs_len = 1;

    // Range 0-100: guard at 50, dog at 75 = 2.
    try std.testing.expectEqual(@as(u32, 2), idaptik_ums_enemies_in_range(&level, 0.0, 100.0));
    // Range 150-250: guard at 200 = 1.
    try std.testing.expectEqual(@as(u32, 1), idaptik_ums_enemies_in_range(&level, 150.0, 250.0));
}

test "highest guard rank" {
    var level = std.mem.zeroes(types.LevelData);
    try std.testing.expectEqual(@as(u8, 255), idaptik_ums_highest_guard_rank(&level));

    level.guards[0] = .{
        .world_x = .{ .position = 0.0 },
        .zone = null,
        .rank = .basic_guard,
        .patrol_radius = 10.0,
    };
    level.guards[1] = .{
        .world_x = .{ .position = 100.0 },
        .zone = null,
        .rank = .sentinel,
        .patrol_radius = 20.0,
    };
    level.guards_len = 2;

    try std.testing.expectEqual(@as(u8, @intFromEnum(types.GuardRank.sentinel)), idaptik_ums_highest_guard_rank(&level));
}
