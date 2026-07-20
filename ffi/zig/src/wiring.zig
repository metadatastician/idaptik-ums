// SPDX-License-Identifier: MPL-2.0
// wiring.zig -- FFI operations for hardware wiring challenges.
// Author: Jonathan D.A. Jewell
//
// Companion to Wiring.idr.  Provides C-ABI functions for:
//   - Adding wiring challenges to a level
//   - Querying by device IP or difficulty
//   - Average difficulty calculation for balance analysis
//
// Wiring challenges are physical puzzles where Jessica must connect, splice,
// or re-route cables/fibres at a specific device.  The difficulty determines
// the minigame complexity and time pressure.

const std = @import("std");
const types = @import("types");

// =========================================================================
// Add function
// =========================================================================

/// Append a wiring challenge to the level.
///
/// Returns `true` on success, `false` if at capacity or null pointer.
pub export fn idaptik_ums_add_wiring(
    level: ?*types.LevelData,
    challenge: ?*const types.WiringChallenge,
) callconv(.c) bool {
    const lv = level orelse return false;
    const ch = challenge orelse return false;
    if (lv.wiring_len >= types.MAX_WIRING) return false;
    lv.wiring[lv.wiring_len] = ch.*;
    lv.wiring_len += 1;
    return true;
}

// =========================================================================
// Query functions
// =========================================================================

/// Count wiring challenges of a specific type.
pub export fn idaptik_ums_count_wiring_by_type(
    level: ?*const types.LevelData,
    wiring_type: u8,
) callconv(.c) u32 {
    const lv = level orelse return 0;
    const target: types.WiringType = @enumFromInt(wiring_type);
    var count: u32 = 0;
    for (lv.wiring[0..lv.wiring_len]) |w| {
        if (w.kind == target) count += 1;
    }
    return count;
}

/// Count wiring challenges attached to a specific device IP.
pub export fn idaptik_ums_wiring_at_device(
    level: ?*const types.LevelData,
    ip: ?*const types.IpAddress,
) callconv(.c) u32 {
    const lv = level orelse return 0;
    const needle = ip orelse return 0;
    var count: u32 = 0;
    for (lv.wiring[0..lv.wiring_len]) |w| {
        if (needle.eql(w.device_ip)) count += 1;
    }
    return count;
}

/// Get the maximum wiring challenge difficulty in the level.
///
/// Returns 0 if no wiring challenges exist.
pub export fn idaptik_ums_max_wiring_difficulty(
    level: ?*const types.LevelData,
) callconv(.c) u32 {
    const lv = level orelse return 0;
    var max_diff: u32 = 0;
    for (lv.wiring[0..lv.wiring_len]) |w| {
        if (w.difficulty > max_diff) max_diff = w.difficulty;
    }
    return max_diff;
}

/// Compute the average wiring difficulty (integer, rounded down).
///
/// Returns 0 if no wiring challenges exist.  Used by the balance analyser
/// to assess level-wide puzzle difficulty.
pub export fn idaptik_ums_avg_wiring_difficulty(
    level: ?*const types.LevelData,
) callconv(.c) u32 {
    const lv = level orelse return 0;
    if (lv.wiring_len == 0) return 0;
    var total: u32 = 0;
    for (lv.wiring[0..lv.wiring_len]) |w| {
        total += w.difficulty;
    }
    return total / lv.wiring_len;
}

/// Get a wiring challenge by index.  Returns null if out of bounds.
pub export fn idaptik_ums_get_wiring(
    level: ?*const types.LevelData,
    index: u32,
) callconv(.c) ?*const types.WiringChallenge {
    const lv = level orelse return null;
    if (index >= lv.wiring_len) return null;
    return &lv.wiring[index];
}

// =========================================================================
// Tests
// =========================================================================

test "add wiring and query by type" {
    var level = std.mem.zeroes(types.LevelData);

    const patch = types.WiringChallenge{
        .kind = .patch_panel,
        .device_ip = types.IpAddress.init(10, 0, 0, 1),
        .difficulty = 3,
    };

    const fibre = types.WiringChallenge{
        .kind = .fibre_splicing,
        .device_ip = types.IpAddress.init(10, 0, 0, 2),
        .difficulty = 7,
    };

    try std.testing.expect(idaptik_ums_add_wiring(&level, &patch));
    try std.testing.expect(idaptik_ums_add_wiring(&level, &fibre));
    try std.testing.expect(idaptik_ums_add_wiring(&level, &patch));

    try std.testing.expectEqual(@as(u32, 3), level.wiring_len);
    try std.testing.expectEqual(@as(u32, 2), idaptik_ums_count_wiring_by_type(&level, @intFromEnum(types.WiringType.patch_panel)));
    try std.testing.expectEqual(@as(u32, 1), idaptik_ums_count_wiring_by_type(&level, @intFromEnum(types.WiringType.fibre_splicing)));
}

test "wiring at device" {
    var level = std.mem.zeroes(types.LevelData);

    const ip1 = types.IpAddress.init(10, 0, 0, 1);
    const ip2 = types.IpAddress.init(10, 0, 0, 2);

    const ch1 = types.WiringChallenge{ .kind = .patch_panel, .device_ip = ip1, .difficulty = 2 };
    const ch2 = types.WiringChallenge{ .kind = .server_rack, .device_ip = ip1, .difficulty = 5 };
    const ch3 = types.WiringChallenge{ .kind = .pbx_comms, .device_ip = ip2, .difficulty = 4 };

    _ = idaptik_ums_add_wiring(&level, &ch1);
    _ = idaptik_ums_add_wiring(&level, &ch2);
    _ = idaptik_ums_add_wiring(&level, &ch3);

    try std.testing.expectEqual(@as(u32, 2), idaptik_ums_wiring_at_device(&level, &ip1));
    try std.testing.expectEqual(@as(u32, 1), idaptik_ums_wiring_at_device(&level, &ip2));
}

test "difficulty stats" {
    var level = std.mem.zeroes(types.LevelData);

    const easy = types.WiringChallenge{ .kind = .patch_panel, .device_ip = types.IpAddress.init(10, 0, 0, 1), .difficulty = 2 };
    const hard = types.WiringChallenge{ .kind = .fibre_splicing, .device_ip = types.IpAddress.init(10, 0, 0, 2), .difficulty = 8 };

    _ = idaptik_ums_add_wiring(&level, &easy);
    _ = idaptik_ums_add_wiring(&level, &hard);

    try std.testing.expectEqual(@as(u32, 8), idaptik_ums_max_wiring_difficulty(&level));
    try std.testing.expectEqual(@as(u32, 5), idaptik_ums_avg_wiring_difficulty(&level)); // (2+8)/2 = 5
}
