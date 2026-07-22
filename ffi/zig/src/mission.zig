// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// mission.zig -- FFI operations for mission objectives and configuration.
// Author: Jonathan D.A. Jewell
//
// Companion to Mission.idr.  Provides C-ABI functions for:
//   - Adding objectives to a mission config
//   - Querying mission state (required count, completion checks)
//   - Time limit helpers
//
// The basic set_mission export lives in main.zig.
// This module adds objective-level granularity.

const std = @import("std");
const types = @import("types");

// =========================================================================
// Objective management
// =========================================================================

/// Add an objective to the level's mission config.
///
/// Returns `true` on success, `false` if at capacity or null pointer.
/// Objectives are appended to the mission's objectives array.
pub export fn idaptik_ums_add_objective(
    level: ?*types.LevelData,
    objective: ?*const types.MissionObjective,
) callconv(.c) bool {
    const lv = level orelse return false;
    const obj = objective orelse return false;

    // The MissionConfig has a dynamic pointer + length.  For the FFI,
    // we store objectives in a separate fixed array within this module
    // and point the MissionConfig at it.  However, because LevelData
    // uses a fixed MissionConfig, we need a side buffer.
    //
    // Since MissionConfig.objectives is a pointer (not inline array),
    // we use a static buffer approach with MAX_OBJECTIVES cap.
    return addObjectiveToBuffer(lv, obj);
}

/// Static per-level objective buffer.
/// The MissionConfig.objectives pointer is set to point into this buffer.
/// Thread-safety: NOT thread-safe — single-threaded level editing only.
var objective_buffer: [types.MAX_OBJECTIVES]types.MissionObjective = undefined;
var objective_count: u32 = 0;

fn addObjectiveToBuffer(
    lv: *types.LevelData,
    obj: *const types.MissionObjective,
) bool {
    if (objective_count >= types.MAX_OBJECTIVES) return false;
    objective_buffer[objective_count] = obj.*;
    objective_count += 1;
    lv.mission.objectives = &objective_buffer;
    lv.mission.objectives_len = objective_count;
    return true;
}

/// Reset the objective buffer.  Call this before building a new mission.
pub export fn idaptik_ums_reset_objectives() callconv(.c) void {
    objective_count = 0;
}

// =========================================================================
// Query functions
// =========================================================================

/// Count the number of required objectives in the mission.
pub export fn idaptik_ums_required_objective_count(
    level: ?*const types.LevelData,
) callconv(.c) u32 {
    const lv = level orelse return 0;
    const objs = lv.mission.objectives orelse return 0;
    var count: u32 = 0;
    for (objs[0..lv.mission.objectives_len]) |obj| {
        if (obj.required) count += 1;
    }
    return count;
}

/// Count the total number of objectives.
pub export fn idaptik_ums_total_objective_count(
    level: ?*const types.LevelData,
) callconv(.c) u32 {
    const lv = level orelse return 0;
    return lv.mission.objectives_len;
}

/// Check whether the mission has a time limit.
pub export fn idaptik_ums_has_time_limit(
    level: ?*const types.LevelData,
) callconv(.c) bool {
    const lv = level orelse return false;
    return lv.mission.has_time_limit;
}

/// Get the time limit in seconds (0 if no time limit).
pub export fn idaptik_ums_get_time_limit(
    level: ?*const types.LevelData,
) callconv(.c) u32 {
    const lv = level orelse return 0;
    if (!lv.mission.has_time_limit) return 0;
    return lv.mission.time_limit;
}

/// Get an objective by index.  Returns null if out of bounds.
pub export fn idaptik_ums_get_objective(
    level: ?*const types.LevelData,
    index: u32,
) callconv(.c) ?*const types.MissionObjective {
    const lv = level orelse return null;
    const objs = lv.mission.objectives orelse return null;
    if (index >= lv.mission.objectives_len) return null;
    return &objs[index];
}

// =========================================================================
// Tests
// =========================================================================

test "add and count objectives" {
    var level = std.mem.zeroes(types.LevelData);
    idaptik_ums_reset_objectives();

    const required_obj = types.MissionObjective{
        .id = null,
        .description = null,
        .required = true,
    };

    const optional_obj = types.MissionObjective{
        .id = null,
        .description = null,
        .required = false,
    };

    try std.testing.expect(idaptik_ums_add_objective(&level, &required_obj));
    try std.testing.expect(idaptik_ums_add_objective(&level, &optional_obj));
    try std.testing.expect(idaptik_ums_add_objective(&level, &required_obj));

    try std.testing.expectEqual(@as(u32, 3), idaptik_ums_total_objective_count(&level));
    try std.testing.expectEqual(@as(u32, 2), idaptik_ums_required_objective_count(&level));
}

test "time limit queries" {
    var level = std.mem.zeroes(types.LevelData);

    try std.testing.expect(!idaptik_ums_has_time_limit(&level));
    try std.testing.expectEqual(@as(u32, 0), idaptik_ums_get_time_limit(&level));

    level.mission.has_time_limit = true;
    level.mission.time_limit = 300;

    try std.testing.expect(idaptik_ums_has_time_limit(&level));
    try std.testing.expectEqual(@as(u32, 300), idaptik_ums_get_time_limit(&level));
}
