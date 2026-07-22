// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// ipc_handlers.zig -- IPC command handlers for IDApTIK UMS.
// Author: Jonathan D.A. Jewell
//
// These functions implement 18 host IPC callbacks: 6 disk/system commands
// plus 12 level-building commands that wrap the C FFI exports from main.zig.
//
// Each function matches the BindingCallback signature:
//   fn([*:0]const u8) callconv(.c) [*:0]const u8
//
// Input:  JSON-encoded request string (from JavaScript via IPC bridge)
// Output: JSON-encoded response string (returned to JavaScript)
//
// Disk/System Commands (6):
//   1. load_level         -- Read a level JSON file from disk
//   2. save_level         -- Write a level JSON file to disk
//   3. validate_level_abi -- Run the 5 ABI validation checks
//   4. list_levels        -- List all saved level files
//   5. export_level_config -- Export level as JSON string
//   6. get_system_info    -- Return system metadata
//
// Level-Building Commands (12):
//   7.  create_level       -- Allocate a new empty LevelData
//   8.  destroy_level      -- Free a LevelData
//   9.  add_zone           -- Append a zone to the level
//  10.  add_device         -- Append a device to the level
//  11.  add_guard          -- Append a guard to the level
//  12.  add_dog            -- Append a dog to the level
//  13.  add_drone          -- Append a drone to the level
//  14.  set_mission        -- Set mission parameters
//  15.  set_physical       -- Set physical world parameters
//  16.  validate_level     -- Run runtime validation (4 checks)
//  17.  serialize_level    -- Serialise LevelData to JSON
//  18.  deserialize_level  -- Deserialise JSON to LevelData
//
// The level storage path is /tmp/idaptik-ums/levels/ (development) or
// ~/.idaptik-ums/levels/ (production). The host must grant a
// capability scope covering exactly these two prefixes, or every disk
// command here fails at runtime: /tmp/idaptik-ums/levels/**, $HOME/.idaptik-ums/**

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types");

/// Shared allocator for IPC response strings.
/// Responses are allocated here and must remain valid until the next call.
/// The host bridge copies the response before the callback returns.
var gpa = std.heap.c_allocator;

/// Base path for level storage.
const LEVELS_DIR = "/tmp/idaptik-ums/levels";

//==============================================================================
// Helper: Extract a JSON string field from a simple JSON object
//==============================================================================

/// Extract the value of "key" from a flat JSON object string.
/// Returns the unescaped value, or null if not found.
fn extractField(json: []const u8, key: []const u8) ?[]const u8 {
    // Look for "key":"value" pattern
    var search_buf: [128]u8 = undefined;
    const prefix = std.fmt.bufPrint(&search_buf, "\"{s}\":\"", .{key}) catch return null;

    const start_idx = std.mem.indexOf(u8, json, prefix) orelse return null;
    const value_start = start_idx + prefix.len;

    // Find the closing quote
    var i: usize = value_start;
    while (i < json.len) : (i += 1) {
        if (json[i] == '"' and (i == 0 or json[i - 1] != '\\')) {
            return json[value_start..i];
        }
    }
    return null;
}

/// Allocate a null-terminated copy of a string for returning via C ABI.
fn allocResponse(data: []const u8) [*:0]const u8 {
    const result = gpa.dupeZ(u8, data) catch return "{}";
    return result;
}

//==============================================================================
// Command 1: load_level
//==============================================================================

/// Load a level JSON file from disk.
///
/// Input JSON:  {"name":"my-level"} or {"path":"/tmp/idaptik-ums/levels/my-level.json"}
/// Output JSON: the level data, or {"error":"..."}
export fn ipc_load_level(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const input = std.mem.span(payload);

    // Extract the level name or path
    const name = extractField(input, "name") orelse
        extractField(input, "path") orelse {
        return allocResponse("{\"error\":\"Missing 'name' or 'path' field\"}");
    };

    // Build the full path
    var path_buf: [512]u8 = undefined;
    const path = if (std.mem.endsWith(u8, name, ".json"))
        std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ LEVELS_DIR, name }) catch
            return allocResponse("{\"error\":\"Path too long\"}")
    else
        std.fmt.bufPrint(&path_buf, "{s}/{s}.json", .{ LEVELS_DIR, name }) catch
            return allocResponse("{\"error\":\"Path too long\"}");

    // Read the file
    const file = std.fs.openFileAbsolute(path, .{ .mode = .read_only }) catch {
        return allocResponse("{\"error\":\"Level file not found\"}");
    };
    defer file.close();

    const contents = file.readToEndAlloc(gpa, 10 * 1024 * 1024) catch {
        return allocResponse("{\"error\":\"Failed to read level file\"}");
    };
    defer gpa.free(contents);

    return allocResponse(contents);
}

//==============================================================================
// Command 2: save_level
//==============================================================================

/// Save level JSON data to disk.
///
/// Input JSON:  {"name":"my-level","level":{...level data...}}
/// Output JSON: {"path":"/tmp/idaptik-ums/levels/my-level.json"}
export fn ipc_save_level(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const input = std.mem.span(payload);

    const name = extractField(input, "name") orelse {
        return allocResponse("{\"error\":\"Missing 'name' field\"}");
    };

    // Ensure the levels directory exists
    std.fs.makeDirAbsolute(LEVELS_DIR) catch |err| {
        if (err != error.PathAlreadyExists) {
            return allocResponse("{\"error\":\"Failed to create levels directory\"}");
        }
    };

    // Build the path
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/{s}.json", .{ LEVELS_DIR, name }) catch
        return allocResponse("{\"error\":\"Path too long\"}");

    // Extract the level data (everything after "level":)
    // For simplicity, write the entire payload as the level file
    const file = std.fs.createFileAbsolute(path, .{}) catch {
        return allocResponse("{\"error\":\"Failed to create level file\"}");
    };
    defer file.close();

    file.writeAll(input) catch {
        return allocResponse("{\"error\":\"Failed to write level file\"}");
    };

    // Return the path
    var response_buf: [600]u8 = undefined;
    const response = std.fmt.bufPrint(&response_buf, "{{\"path\":\"{s}\"}}", .{path}) catch
        return allocResponse("{\"error\":\"Response too long\"}");

    return allocResponse(response);
}

//==============================================================================
// Command 3: validate_level_abi
//==============================================================================

/// Import the FFI exports from main.zig for deserialisation and validation.
/// These are C ABI functions exported by the same library.
extern fn idaptik_ums_deserialize_level(data: ?[*]const u8, data_len: usize) callconv(.c) ?*types.LevelData;
extern fn idaptik_ums_validate_level(level: ?*const types.LevelData) callconv(.c) types.ValidationResult;
extern fn idaptik_ums_destroy_level(level: ?*types.LevelData) callconv(.c) void;

/// Run the 5 ABI validation checks on a level.
///
/// Input JSON:  {"level":{...}} or the full level JSON directly
/// Output JSON: {"valid":true,"defence_targets_valid":true,"guards_in_zones":true,
///               "zones_ordered":true,"pbx_consistent":true}
///
/// Deserialises the JSON payload into a LevelData struct, runs all four
/// cross-domain proof checks (defence targets, guards-in-zones, zones-ordered,
/// PBX-consistent), and returns the results as JSON.
export fn ipc_validate_level_abi(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const input = std.mem.span(payload);

    // The payload may be {"level":{...}} or the level JSON directly.
    // Try to extract the "level" field; if not found, treat the whole
    // payload as the level JSON.
    const level_json = extractLevelJson(input) orelse input;

    if (level_json.len == 0) {
        return allocResponse("{\"error\":\"Empty level data\"}");
    }

    // Deserialise the JSON into a LevelData struct via the C FFI.
    const level = idaptik_ums_deserialize_level(level_json.ptr, level_json.len) orelse {
        return allocResponse("{\"error\":\"Failed to deserialise level JSON\"}");
    };
    defer idaptik_ums_destroy_level(level);

    // Run all four validation checks.
    const result = idaptik_ums_validate_level(level);

    // Format the validation result as JSON.
    var buf: [256]u8 = undefined;
    const response = std.fmt.bufPrint(
        &buf,
        "{{\"valid\":{},\"defence_targets_valid\":{},\"guards_in_zones\":{},\"zones_ordered\":{},\"pbx_consistent\":{}}}",
        .{ result.valid, result.defence_targets_valid, result.guards_in_zones, result.zones_ordered, result.pbx_consistent },
    ) catch return allocResponse("{\"error\":\"Response buffer overflow\"}");

    return allocResponse(response);
}

/// Extract the value of the "level" field from a JSON object.
/// Finds the substring after "level": and returns the JSON value
/// (accounting for nested braces).
fn extractLevelJson(json: []const u8) ?[]const u8 {
    const marker = "\"level\":";
    const start_idx = std.mem.indexOf(u8, json, marker) orelse return null;
    const value_start = start_idx + marker.len;

    // Skip whitespace
    var i = value_start;
    while (i < json.len and (json[i] == ' ' or json[i] == '\t' or json[i] == '\n')) : (i += 1) {}
    if (i >= json.len) return null;

    // The level value should be a JSON object starting with '{'
    if (json[i] != '{') return null;

    // Find the matching closing brace
    var depth: usize = 0;
    var in_string = false;
    var j = i;
    while (j < json.len) : (j += 1) {
        if (in_string) {
            if (json[j] == '\\' and j + 1 < json.len) {
                j += 1; // Skip escaped character
            } else if (json[j] == '"') {
                in_string = false;
            }
        } else {
            switch (json[j]) {
                '"' => in_string = true,
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if (depth == 0) return json[i .. j + 1];
                },
                else => {},
            }
        }
    }
    return null;
}

//==============================================================================
// Command 4: list_levels
//==============================================================================

/// List all saved level files.
///
/// Input JSON:  {} (no parameters)
/// Output JSON: [{"name":"level1","path":"/tmp/..."},...]
export fn ipc_list_levels(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    _ = payload;

    // Ensure the levels directory exists
    std.fs.makeDirAbsolute(LEVELS_DIR) catch |err| {
        if (err != error.PathAlreadyExists) {
            return allocResponse("[]");
        }
    };

    var dir = std.fs.openDirAbsolute(LEVELS_DIR, .{ .iterate = true }) catch {
        return allocResponse("[]");
    };
    defer dir.close();

    // Build a JSON array of level entries
    var result = std.ArrayListUnmanaged(u8){};
    defer result.deinit(gpa);

    result.appendSlice(gpa, "[") catch return allocResponse("[]");

    var first = true;
    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        const name = entry.name;
        if (!std.mem.endsWith(u8, name, ".json")) continue;

        // Strip .json extension for display name
        const display_name = name[0 .. name.len - 5];

        if (!first) {
            result.appendSlice(gpa, ",") catch continue;
        }
        first = false;

        // Build entry JSON
        var entry_buf: [1024]u8 = undefined;
        const entry_json = std.fmt.bufPrint(
            &entry_buf,
            "{{\"name\":\"{s}\",\"path\":\"{s}/{s}\"}}",
            .{ display_name, LEVELS_DIR, name },
        ) catch continue;

        result.appendSlice(gpa, entry_json) catch continue;
    }

    result.appendSlice(gpa, "]") catch return allocResponse("[]");

    const owned = result.toOwnedSlice(gpa) catch return allocResponse("[]");
    defer gpa.free(owned);
    return allocResponse(owned);
}

//==============================================================================
// Command 5: export_level_config
//==============================================================================

/// Export level data as a JSON configuration string.
///
/// Input JSON:  {"name":"my-level"}
/// Output JSON: the level JSON (same as load_level for now)
export fn ipc_export_level_config(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    // Currently identical to load_level: read the file, return JSON. Kept as a
    // distinct command so export can diverge (filtering, versioning) without
    // breaking callers already bound to this name.
    return ipc_load_level(payload);
}

//==============================================================================
// Command 6: get_system_info
//==============================================================================

/// Return system metadata.
///
/// Input JSON:  {} (no parameters)
/// Output JSON: {"app_name":"IDApTIK UMS","version":"0.2.0","os":"linux",
///               "arch":"x86_64","shell":"gossamer","shell_version":"0.2.0"}
export fn ipc_get_system_info(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    _ = payload;

    const os_name = switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "macos",
        .windows => "windows",
        .freebsd => "freebsd",
        .openbsd => "openbsd",
        .netbsd => "netbsd",
        .ios => "ios",
        else => "unknown",
    };

    const arch_name = switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        .riscv64 => "riscv64",
        .arm => "arm",
        .wasm32 => "wasm32",
        else => "unknown",
    };

    var buf: [512]u8 = undefined;
    const response = std.fmt.bufPrint(
        &buf,
        "{{\"app_name\":\"IDApTIK UMS\",\"version\":\"0.2.0\",\"os\":\"{s}\",\"arch\":\"{s}\",\"shell\":\"gossamer\",\"shell_version\":\"0.2.0\"}}",
        .{ os_name, arch_name },
    ) catch return allocResponse("{\"error\":\"Buffer overflow\"}");

    return allocResponse(response);
}

//==============================================================================
// Level-Building Commands (12): wrappers around the C FFI exports
//==============================================================================

/// Global active level handle. The IPC bridge maintains exactly one active
/// level at a time. `create_level` allocates it; `destroy_level` frees it.
/// All `add_*`, `set_*`, `validate_level`, and `serialize_level` commands
/// operate on this handle. This matches the linear-handle pattern in
/// LevelEditor.eph where the handle flows through borrow chains.
var active_level: ?*types.LevelData = null;

/// Import the C FFI exports from main.zig for level building.
extern fn idaptik_ums_create_level() callconv(.c) ?*types.LevelData;
extern fn idaptik_ums_add_device(level: ?*types.LevelData, spec: ?*const types.DeviceSpec) callconv(.c) bool;
extern fn idaptik_ums_add_zone(level: ?*types.LevelData, zone: ?*const types.Zone) callconv(.c) bool;
extern fn idaptik_ums_add_guard(level: ?*types.LevelData, guard: ?*const types.GuardPlacement) callconv(.c) bool;
extern fn idaptik_ums_add_dog(level: ?*types.LevelData, dog: ?*const types.DogPlacement) callconv(.c) bool;
extern fn idaptik_ums_add_drone(level: ?*types.LevelData, drone: ?*const types.DronePlacement) callconv(.c) bool;
extern fn idaptik_ums_set_mission(level: ?*types.LevelData, mission: ?*const types.MissionConfig) callconv(.c) bool;
extern fn idaptik_ums_set_physical(level: ?*types.LevelData, physical: ?*const types.PhysicalConfig) callconv(.c) bool;
extern fn idaptik_ums_serialize_level(level: ?*const types.LevelData, buf: ?[*]u8, buf_len: usize) callconv(.c) usize;

//==============================================================================
// Command 7: create_level
//==============================================================================

/// Allocate a new empty LevelData and store it as the active level.
///
/// Input JSON:  {} (no parameters — previous level is destroyed first)
/// Output JSON: {"ok":true} or {"error":"..."}
export fn ipc_create_level(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    _ = payload;

    // Destroy the previous active level if one exists.
    if (active_level) |prev| {
        idaptik_ums_destroy_level_ext(prev);
    }

    const level = idaptik_ums_create_level() orelse {
        return allocResponse("{\"error\":\"Failed to allocate level\"}");
    };

    active_level = level;
    return allocResponse("{\"ok\":true}");
}

//==============================================================================
// Command 8: destroy_level
//==============================================================================

/// Free the active LevelData and set the handle to null.
///
/// Input JSON:  {} (no parameters)
/// Output JSON: {"ok":true}
export fn ipc_destroy_level(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    _ = payload;

    if (active_level) |level| {
        idaptik_ums_destroy_level_ext(level);
        active_level = null;
    }

    return allocResponse("{\"ok\":true}");
}

//==============================================================================
// Command 9: add_zone
//==============================================================================

/// Add a zone to the active level.
///
/// Input JSON:  {"name":"Zone A","security_tier":2}
/// Output JSON: {"ok":true} or {"error":"..."}
export fn ipc_add_zone(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const level = active_level orelse {
        return allocResponse("{\"error\":\"No active level — call create_level first\"}");
    };

    const input = std.mem.span(payload);
    const name_str = extractField(input, "name") orelse {
        return allocResponse("{\"error\":\"Missing 'name' field\"}");
    };

    // Allocate a persistent copy of the zone name for the C ABI.
    const name_z = gpa.dupeZ(u8, name_str) catch {
        return allocResponse("{\"error\":\"Out of memory\"}");
    };

    const tier = extractU32Field(input, "security_tier") orelse 0;

    var zone = types.Zone{
        .name = name_z.ptr,
        .security_tier = tier,
    };

    if (!idaptik_ums_add_zone(level, &zone)) {
        return allocResponse("{\"error\":\"Zone array at capacity\"}");
    }

    return allocResponse("{\"ok\":true}");
}

//==============================================================================
// Command 10: add_device
//==============================================================================

/// Add a device to the active level.
///
/// Input JSON:  {"kind":0,"ip":"192.168.1.1","name":"Router","security":2}
/// Output JSON: {"ok":true} or {"error":"..."}
export fn ipc_add_device(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const level = active_level orelse {
        return allocResponse("{\"error\":\"No active level — call create_level first\"}");
    };

    const input = std.mem.span(payload);
    const kind_val = extractU8Field(input, "kind") orelse 0;
    const security_val = extractU8Field(input, "security") orelse 0;
    const ip_str = extractField(input, "ip") orelse "0.0.0.0";
    const name_str = extractField(input, "name");

    const ip = parseIpStringLocal(ip_str) catch types.IpAddress.init(0, 0, 0, 0);

    // Allocate a persistent copy of the device name.
    var name_ptr: ?[*:0]const u8 = null;
    if (name_str) |ns| {
        const name_zz = gpa.dupeZ(u8, ns) catch {
            return allocResponse("{\"error\":\"Out of memory\"}");
        };
        name_ptr = name_zz.ptr;
    }

    var spec = types.DeviceSpec{
        .kind = @enumFromInt(kind_val),
        .ip = ip,
        .name = name_ptr,
        .security = @enumFromInt(security_val),
    };

    if (!idaptik_ums_add_device(level, &spec)) {
        return allocResponse("{\"error\":\"Device array at capacity\"}");
    }

    return allocResponse("{\"ok\":true}");
}

//==============================================================================
// Command 11: add_guard
//==============================================================================

/// Add a guard to the active level.
///
/// Input JSON:  {"world_x":100.0,"zone":"Zone A","rank":1,"patrol_radius":50.0}
/// Output JSON: {"ok":true} or {"error":"..."}
export fn ipc_add_guard(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const level = active_level orelse {
        return allocResponse("{\"error\":\"No active level — call create_level first\"}");
    };

    const input = std.mem.span(payload);
    const zone_str = extractField(input, "zone") orelse {
        return allocResponse("{\"error\":\"Missing 'zone' field\"}");
    };
    const rank_val = extractU8Field(input, "rank") orelse 0;
    const world_x = extractF64Field(input, "world_x") orelse 0.0;
    const patrol_radius = extractF64Field(input, "patrol_radius") orelse 50.0;

    const zone_z = gpa.dupeZ(u8, zone_str) catch {
        return allocResponse("{\"error\":\"Out of memory\"}");
    };

    var guard = types.GuardPlacement{
        .world_x = .{ .position = world_x },
        .zone = zone_z.ptr,
        .rank = @enumFromInt(rank_val),
        .patrol_radius = patrol_radius,
    };

    if (!idaptik_ums_add_guard(level, &guard)) {
        return allocResponse("{\"error\":\"Guard array at capacity\"}");
    }

    return allocResponse("{\"ok\":true}");
}

//==============================================================================
// Command 12: add_dog
//==============================================================================

/// Add a security dog to the active level.
///
/// Input JSON:  {"world_x":200.0,"breed":0,"patrol_radius":30.0}
/// Output JSON: {"ok":true} or {"error":"..."}
export fn ipc_add_dog(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const level = active_level orelse {
        return allocResponse("{\"error\":\"No active level — call create_level first\"}");
    };

    const input = std.mem.span(payload);
    const breed_val = extractU8Field(input, "breed") orelse 0;
    const world_x = extractF64Field(input, "world_x") orelse 0.0;
    const patrol_radius = extractF64Field(input, "patrol_radius") orelse 30.0;

    var dog = types.DogPlacement{
        .world_x = .{ .position = world_x },
        .breed = @enumFromInt(breed_val),
        .patrol_radius = patrol_radius,
    };

    if (!idaptik_ums_add_dog(level, &dog)) {
        return allocResponse("{\"error\":\"Dog array at capacity\"}");
    }

    return allocResponse("{\"ok\":true}");
}

//==============================================================================
// Command 13: add_drone
//==============================================================================

/// Add a drone to the active level.
///
/// Input JSON:  {"world_x":300.0,"archetype":1,"altitude":100.0}
/// Output JSON: {"ok":true} or {"error":"..."}
export fn ipc_add_drone(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const level = active_level orelse {
        return allocResponse("{\"error\":\"No active level — call create_level first\"}");
    };

    const input = std.mem.span(payload);
    const arch_val = extractU8Field(input, "archetype") orelse 0;
    const world_x = extractF64Field(input, "world_x") orelse 0.0;
    const altitude = extractF64Field(input, "altitude") orelse 50.0;

    var drone = types.DronePlacement{
        .world_x = .{ .position = world_x },
        .archetype = @enumFromInt(arch_val),
        .altitude = altitude,
    };

    if (!idaptik_ums_add_drone(level, &drone)) {
        return allocResponse("{\"error\":\"Drone array at capacity\"}");
    }

    return allocResponse("{\"ok\":true}");
}

//==============================================================================
// Command 14: set_mission
//==============================================================================

/// Set mission parameters on the active level.
///
/// Input JSON:  {"mission_id":"m01","location_id":"loc01","has_time_limit":true,"time_limit":300}
/// Output JSON: {"ok":true} or {"error":"..."}
export fn ipc_set_mission(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const level = active_level orelse {
        return allocResponse("{\"error\":\"No active level — call create_level first\"}");
    };

    const input = std.mem.span(payload);
    const mission_id_str = extractField(input, "mission_id");
    const location_id_str = extractField(input, "location_id");
    const has_time_limit = extractBoolField(input, "has_time_limit") orelse false;
    const time_limit = extractU32Field(input, "time_limit") orelse 0;

    var mission_id_z: ?[*:0]const u8 = null;
    if (mission_id_str) |ms| {
        const z = gpa.dupeZ(u8, ms) catch return allocResponse("{\"error\":\"Out of memory\"}");
        mission_id_z = z.ptr;
    }

    var location_id_z: ?[*:0]const u8 = null;
    if (location_id_str) |ls| {
        const z = gpa.dupeZ(u8, ls) catch return allocResponse("{\"error\":\"Out of memory\"}");
        location_id_z = z.ptr;
    }

    var mission = types.MissionConfig{
        .mission_id = mission_id_z,
        .location_id = location_id_z,
        .objectives = null,
        .objectives_len = 0,
        .has_time_limit = has_time_limit,
        .time_limit = time_limit,
    };

    if (!idaptik_ums_set_mission(level, &mission)) {
        return allocResponse("{\"error\":\"Failed to set mission\"}");
    }

    return allocResponse("{\"ok\":true}");
}

//==============================================================================
// Command 15: set_physical
//==============================================================================

/// Set physical world parameters on the active level.
///
/// Input JSON:  {"ground_y":500.0,"world_width":2400.0,"interaction_distance":80.0,
///               "has_power_system":true,"has_security_cameras":false,
///               "number_of_covert_links":3}
/// Output JSON: {"ok":true} or {"error":"..."}
export fn ipc_set_physical(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const level = active_level orelse {
        return allocResponse("{\"error\":\"No active level — call create_level first\"}");
    };

    const input = std.mem.span(payload);
    const ground_y = extractF64Field(input, "ground_y") orelse 0.0;
    const world_width = extractF64Field(input, "world_width") orelse 0.0;
    const interaction_distance = extractF64Field(input, "interaction_distance") orelse 80.0;
    const has_power = extractBoolField(input, "has_power_system") orelse false;
    const has_cameras = extractBoolField(input, "has_security_cameras") orelse false;
    const covert_links = extractU32Field(input, "number_of_covert_links") orelse 0;

    var physical = types.PhysicalConfig{
        .ground_y = ground_y,
        .world_width = world_width,
        .interaction_distance = interaction_distance,
        .has_power_system = has_power,
        .has_security_cameras = has_cameras,
        .number_of_covert_links = covert_links,
    };

    if (!idaptik_ums_set_physical(level, &physical)) {
        return allocResponse("{\"error\":\"Failed to set physical config\"}");
    }

    return allocResponse("{\"ok\":true}");
}

//==============================================================================
// Command 16: validate_level
//==============================================================================

/// Run the 4 runtime validation checks on the active level.
///
/// Input JSON:  {} (no parameters)
/// Output JSON: {"valid":true,"defence_targets_valid":true,"guards_in_zones":true,
///               "zones_ordered":true,"pbx_consistent":true}
export fn ipc_validate_level(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    _ = payload;

    const level = active_level orelse {
        return allocResponse("{\"error\":\"No active level — call create_level first\"}");
    };

    const result = idaptik_ums_validate_level(level);

    var buf: [256]u8 = undefined;
    const resp = std.fmt.bufPrint(
        &buf,
        "{{\"valid\":{},\"defence_targets_valid\":{},\"guards_in_zones\":{},\"zones_ordered\":{},\"pbx_consistent\":{}}}",
        .{ result.valid, result.defence_targets_valid, result.guards_in_zones, result.zones_ordered, result.pbx_consistent },
    ) catch return allocResponse("{\"error\":\"Response buffer overflow\"}");

    return allocResponse(resp);
}

//==============================================================================
// Command 17: serialize_level
//==============================================================================

/// Serialise the active level to JSON.
///
/// Input JSON:  {} (no parameters)
/// Output JSON: the level JSON, or {"error":"..."}
export fn ipc_serialize_level(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    _ = payload;

    const level = active_level orelse {
        return allocResponse("{\"error\":\"No active level — call create_level first\"}");
    };

    // Use a 1MB buffer for serialisation.
    const serialize_buf = gpa.alloc(u8, 1024 * 1024) catch {
        return allocResponse("{\"error\":\"Out of memory for serialisation buffer\"}");
    };
    defer gpa.free(serialize_buf);

    const bytes_written = idaptik_ums_serialize_level(level, serialize_buf.ptr, serialize_buf.len);

    if (bytes_written == 0) {
        return allocResponse("{\"error\":\"Serialisation failed or buffer too small\"}");
    }

    return allocResponse(serialize_buf[0..bytes_written]);
}

//==============================================================================
// Command 18: deserialize_level
//==============================================================================

/// Deserialise a JSON string into the active level, replacing any existing one.
///
/// Input JSON:  {"json":"<level JSON string>"} or the level JSON directly
/// Output JSON: {"ok":true} or {"error":"..."}
export fn ipc_deserialize_level(payload: [*:0]const u8) callconv(.c) [*:0]const u8 {
    const input = std.mem.span(payload);

    // The payload itself could be the level JSON, or wrapped as {"json":"..."}.
    // Try extracting "json" field first; fall back to treating entire payload as level.
    const level_json = extractLevelJson(input) orelse
        if (extractField(input, "json")) |j| j else input;

    if (level_json.len == 0) {
        return allocResponse("{\"error\":\"Empty level data\"}");
    }

    // Destroy the previous active level if one exists.
    if (active_level) |prev| {
        idaptik_ums_destroy_level_ext(prev);
    }

    const level = idaptik_ums_deserialize_level(level_json.ptr, level_json.len) orelse {
        active_level = null;
        return allocResponse("{\"error\":\"Failed to deserialise level JSON\"}");
    };

    active_level = level;
    return allocResponse("{\"ok\":true}");
}

//==============================================================================
// Helpers: numeric and boolean field extraction
//==============================================================================

/// Extract a u8 numeric value from a JSON field.
fn extractU8Field(json: []const u8, key: []const u8) ?u8 {
    const val = extractNumericField(json, key) orelse return null;
    if (val < 0 or val > 255) return null;
    return @intCast(@as(i64, @intFromFloat(val)));
}

/// Extract a u32 numeric value from a JSON field.
fn extractU32Field(json: []const u8, key: []const u8) ?u32 {
    const val = extractNumericField(json, key) orelse return null;
    if (val < 0 or val > 4294967295.0) return null;
    return @intCast(@as(i64, @intFromFloat(val)));
}

/// Extract a f64 numeric value from a JSON field.
fn extractF64Field(json: []const u8, key: []const u8) ?f64 {
    return extractNumericField(json, key);
}

/// Extract a boolean value from a JSON field.
/// Looks for "key":true or "key":false in the JSON.
fn extractBoolField(json: []const u8, key: []const u8) ?bool {
    var search_buf: [128]u8 = undefined;
    const prefix = std.fmt.bufPrint(&search_buf, "\"{s}\":", .{key}) catch return null;
    const start_idx = std.mem.indexOf(u8, json, prefix) orelse return null;
    const val_start = start_idx + prefix.len;

    // Skip whitespace.
    var i = val_start;
    while (i < json.len and (json[i] == ' ' or json[i] == '\t')) : (i += 1) {}
    if (i >= json.len) return null;

    if (json.len - i >= 4 and std.mem.eql(u8, json[i..][0..4], "true")) return true;
    if (json.len - i >= 5 and std.mem.eql(u8, json[i..][0..5], "false")) return false;
    return null;
}

/// Extract a numeric value from a JSON field (handles int and float).
fn extractNumericField(json: []const u8, key: []const u8) ?f64 {
    var search_buf: [128]u8 = undefined;
    const prefix = std.fmt.bufPrint(&search_buf, "\"{s}\":", .{key}) catch return null;
    const start_idx = std.mem.indexOf(u8, json, prefix) orelse return null;
    const val_start = start_idx + prefix.len;

    // Skip whitespace.
    var i = val_start;
    while (i < json.len and (json[i] == ' ' or json[i] == '\t')) : (i += 1) {}
    if (i >= json.len) return null;

    // Collect the numeric characters.
    const num_start = i;
    while (i < json.len and (json[i] == '-' or json[i] == '.' or (json[i] >= '0' and json[i] <= '9'))) : (i += 1) {}
    if (i == num_start) return null;

    return std.fmt.parseFloat(f64, json[num_start..i]) catch null;
}

/// Parse an IP address string "a.b.c.d" into an IpAddress (local copy
/// to avoid colliding with the top-level declaration in main.zig).
fn parseIpStringLocal(s: []const u8) !types.IpAddress {
    var octets: [4]u8 = .{ 0, 0, 0, 0 };
    var octet_idx: usize = 0;
    var current: u16 = 0;

    for (s) |c| {
        if (c == '.') {
            if (octet_idx >= 3) return error.InvalidIp;
            if (current > 255) return error.InvalidIp;
            octets[octet_idx] = @intCast(current);
            octet_idx += 1;
            current = 0;
        } else if (c >= '0' and c <= '9') {
            current = current * 10 + (c - '0');
        } else {
            return error.InvalidIp;
        }
    }
    if (octet_idx != 3) return error.InvalidIp;
    if (current > 255) return error.InvalidIp;
    octets[3] = @intCast(current);

    return types.IpAddress.init(octets[0], octets[1], octets[2], octets[3]);
}

/// Alias for the extern destroy function — avoids name collision with the
/// declaration already present for validate_level_abi above.
fn idaptik_ums_destroy_level_ext(level: ?*types.LevelData) void {
    idaptik_ums_destroy_level(level);
}
