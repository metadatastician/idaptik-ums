// SPDX-License-Identifier: MPL-2.0
// inventory.zig -- FFI operations for the IDApTIK item and inventory system.
// Author: Jonathan D.A. Jewell
//
// Companion to Inventory.idr.  Provides C-ABI functions for:
//   - Adding items / world items to a LevelData
//   - Querying inventory state (total weight, item lookup by ID)
//   - Condition degradation (pristine → good → worn → damaged → broken)
//
// All functions operate on the types defined in types.zig and work with
// the LevelData struct from Level.idr / types.zig.

const std = @import("std");
const types = @import("types");

// =========================================================================
// Add functions
// =========================================================================

/// Append a world item to the level's item list.
///
/// Returns `true` on success, `false` if at capacity or null pointer.
pub export fn idaptik_ums_add_item(
    level: ?*types.LevelData,
    item: ?*const types.WorldItem,
) callconv(.c) bool {
    const lv = level orelse return false;
    const it = item orelse return false;
    if (lv.items_len >= types.MAX_ITEMS) return false;
    lv.items[lv.items_len] = it.*;
    lv.items_len += 1;
    return true;
}

/// Append an assassin config to the level's assassin list.
///
/// Returns `true` on success, `false` if at capacity or null pointer.
pub export fn idaptik_ums_add_assassin(
    level: ?*types.LevelData,
    assassin: ?*const types.AssassinConfig,
) callconv(.c) bool {
    const lv = level orelse return false;
    const a = assassin orelse return false;
    if (lv.assassins_len >= types.MAX_ASSASSINS) return false;
    lv.assassins[lv.assassins_len] = a.*;
    lv.assassins_len += 1;
    return true;
}

// =========================================================================
// Query functions
// =========================================================================

/// Compute the total weight of all items in the level.
///
/// This is the runtime equivalent of folding over the Idris2 list with
/// `sum . map weight`.  Returns 0 for an empty or null level.
pub export fn idaptik_ums_total_item_weight(
    level: ?*const types.LevelData,
) callconv(.c) u32 {
    const lv = level orelse return 0;
    var total: u32 = 0;
    for (lv.items[0..lv.items_len]) |world_item| {
        total +|= world_item.item.weight; // Saturating add prevents overflow.
    }
    return total;
}

/// Count items matching a given ItemKindTag.
///
/// Useful for inventory UI summaries (e.g. "3 cables, 2 tools").
pub export fn idaptik_ums_count_items_by_kind(
    level: ?*const types.LevelData,
    kind_tag: u8,
) callconv(.c) u32 {
    const lv = level orelse return 0;
    const target: types.ItemKindTag = @enumFromInt(kind_tag);
    var count: u32 = 0;
    for (lv.items[0..lv.items_len]) |world_item| {
        if (world_item.item.kind.tag == target) count += 1;
    }
    return count;
}

/// Look up an item by index.  Returns null if index is out of bounds.
///
/// The returned pointer is valid as long as the LevelData is not destroyed
/// or the items array is not modified (i.e. no add_item calls).
pub export fn idaptik_ums_get_item(
    level: ?*const types.LevelData,
    index: u32,
) callconv(.c) ?*const types.WorldItem {
    const lv = level orelse return null;
    if (index >= lv.items_len) return null;
    return &lv.items[index];
}

// =========================================================================
// Condition degradation
// =========================================================================

/// Degrade an item's condition by one step.
///
/// Mirrors the Idris2 successor-style degradation:
///   pristine → good → worn → damaged → broken (stays broken).
///
/// Returns the new condition value, or the current value if already broken
/// or the pointer is null.
pub export fn idaptik_ums_degrade_condition(
    level: ?*types.LevelData,
    item_index: u32,
) callconv(.c) u8 {
    const lv = level orelse return @intFromEnum(types.ItemCondition.broken);
    if (item_index >= lv.items_len) return @intFromEnum(types.ItemCondition.broken);

    const current = @intFromEnum(lv.items[item_index].item.condition);
    if (current >= @intFromEnum(types.ItemCondition.broken)) {
        return current;
    }
    const next: types.ItemCondition = @enumFromInt(current + 1);
    lv.items[item_index].item.condition = next;
    return @intFromEnum(next);
}

// =========================================================================
// Tests
// =========================================================================

test "add item and query weight" {
    var level = std.mem.zeroes(types.LevelData);

    const item1 = types.WorldItem{
        .item = .{
            .id = null,
            .kind = .{ .tag = .cable, .sub_type = 0, .capacity = 0, .zone_name = null },
            .name = null,
            .weight = 10,
            .condition = .pristine,
            .has_uses_remaining = false,
            .uses_remaining = 0,
        },
        .world_x = .{ .position = 100.0 },
        .container = null,
    };

    try std.testing.expect(idaptik_ums_add_item(&level, &item1));
    try std.testing.expectEqual(@as(u32, 1), level.items_len);
    try std.testing.expectEqual(@as(u32, 10), idaptik_ums_total_item_weight(&level));
}

test "count items by kind" {
    var level = std.mem.zeroes(types.LevelData);

    const cable_item = types.WorldItem{
        .item = .{
            .id = null,
            .kind = .{ .tag = .cable, .sub_type = 0, .capacity = 0, .zone_name = null },
            .name = null,
            .weight = 5,
            .condition = .good,
            .has_uses_remaining = false,
            .uses_remaining = 0,
        },
        .world_x = .{ .position = 50.0 },
        .container = null,
    };

    const tool_item = types.WorldItem{
        .item = .{
            .id = null,
            .kind = .{ .tag = .tool, .sub_type = 2, .capacity = 0, .zone_name = null },
            .name = null,
            .weight = 15,
            .condition = .pristine,
            .has_uses_remaining = true,
            .uses_remaining = 3,
        },
        .world_x = .{ .position = 75.0 },
        .container = null,
    };

    _ = idaptik_ums_add_item(&level, &cable_item);
    _ = idaptik_ums_add_item(&level, &tool_item);
    _ = idaptik_ums_add_item(&level, &cable_item);

    try std.testing.expectEqual(@as(u32, 2), idaptik_ums_count_items_by_kind(&level, @intFromEnum(types.ItemKindTag.cable)));
    try std.testing.expectEqual(@as(u32, 1), idaptik_ums_count_items_by_kind(&level, @intFromEnum(types.ItemKindTag.tool)));
}

test "degrade condition" {
    var level = std.mem.zeroes(types.LevelData);

    const item = types.WorldItem{
        .item = .{
            .id = null,
            .kind = .{ .tag = .tool, .sub_type = 0, .capacity = 0, .zone_name = null },
            .name = null,
            .weight = 5,
            .condition = .pristine,
            .has_uses_remaining = false,
            .uses_remaining = 0,
        },
        .world_x = .{ .position = 0.0 },
        .container = null,
    };

    _ = idaptik_ums_add_item(&level, &item);

    try std.testing.expectEqual(@as(u8, @intFromEnum(types.ItemCondition.good)), idaptik_ums_degrade_condition(&level, 0));
    try std.testing.expectEqual(@as(u8, @intFromEnum(types.ItemCondition.worn)), idaptik_ums_degrade_condition(&level, 0));
    try std.testing.expectEqual(@as(u8, @intFromEnum(types.ItemCondition.damaged)), idaptik_ums_degrade_condition(&level, 0));
    try std.testing.expectEqual(@as(u8, @intFromEnum(types.ItemCondition.broken)), idaptik_ums_degrade_condition(&level, 0));
    // Already broken — stays broken.
    try std.testing.expectEqual(@as(u8, @intFromEnum(types.ItemCondition.broken)), idaptik_ums_degrade_condition(&level, 0));
}
