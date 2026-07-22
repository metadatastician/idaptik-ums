// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// build.zig -- Build configuration for IDApTIK UMS Zig FFI shared library.
// Author: Jonathan D.A. Jewell
//
// Produces `libidaptik_ums` as a shared (.so / .dylib / .dll) and static (.a)
// library exposing the C-compatible FFI surface defined by the Idris2 ABI
// modules in `../../src/abi/`.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // -- Link libc for c_allocator used by IPC handlers --
    // The ipc_handlers.zig module uses std.heap.c_allocator for IPC
    // response strings. This requires linking against libc.

    // -- Shared modules used by both library targets and tests --

    const types_mod = b.addModule("types", .{
        .root_source_file = b.path("src/types.zig"),
        .target = target,
        .optimize = optimize,
    });

    const validate_mod = b.addModule("validate", .{
        .root_source_file = b.path("src/validate.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = types_mod },
        },
    });

    const ipc_handlers_mod = b.addModule("ipc_handlers", .{
        .root_source_file = b.path("src/ipc_handlers.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = types_mod },
        },
    });

    // -- Domain FFI modules (companions to Idris2 ABI modules) --

    const inventory_mod = b.addModule("inventory", .{
        .root_source_file = b.path("src/inventory.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = types_mod },
        },
    });

    const enemies_mod = b.addModule("enemies", .{
        .root_source_file = b.path("src/enemies.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = types_mod },
        },
    });

    const mission_mod = b.addModule("mission", .{
        .root_source_file = b.path("src/mission.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = types_mod },
        },
    });

    const wiring_mod = b.addModule("wiring", .{
        .root_source_file = b.path("src/wiring.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = types_mod },
        },
    });

    const proven_bridge_mod = b.addModule("proven_bridge", .{
        .root_source_file = b.path("src/proven_bridge.zig"),
        .target = target,
        .optimize = optimize,
    });

    const multiplayer_mod = b.addModule("multiplayer", .{
        .root_source_file = b.path("src/multiplayer.zig"),
        .target = target,
        .optimize = optimize,
    });

    const game_systems_mod = b.addModule("game_systems", .{
        .root_source_file = b.path("src/game_systems.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Common import set for library and test targets.
    const all_imports = &[_]std.Build.Module.Import{
        .{ .name = "types", .module = types_mod },
        .{ .name = "validate", .module = validate_mod },
        .{ .name = "ipc_handlers", .module = ipc_handlers_mod },
        .{ .name = "inventory", .module = inventory_mod },
        .{ .name = "enemies", .module = enemies_mod },
        .{ .name = "mission", .module = mission_mod },
        .{ .name = "wiring", .module = wiring_mod },
        .{ .name = "proven_bridge", .module = proven_bridge_mod },
        .{ .name = "multiplayer", .module = multiplayer_mod },
        .{ .name = "game_systems", .module = game_systems_mod },
    };

    // ---------------------------------------------------------------
    // Shared library: libidaptik_ums
    // ---------------------------------------------------------------
    const shared_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "idaptik_ums",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = all_imports,
        }),
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    b.installArtifact(shared_lib);

    // ---------------------------------------------------------------
    // Static library (for embedding in Rust hosts — the Bevy/Fyrox frontends)
    // ---------------------------------------------------------------
    const static_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "idaptik_ums",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = all_imports,
        }),
    });
    b.installArtifact(static_lib);

    // ---------------------------------------------------------------
    // Main module (for test imports)
    // ---------------------------------------------------------------
    const main_mod = b.addModule("main", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = all_imports,
    });

    // ---------------------------------------------------------------
    // Integration tests
    // ---------------------------------------------------------------
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/integration_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "types", .module = types_mod },
                .{ .name = "validate", .module = validate_mod },
                .{ .name = "main", .module = main_mod },
                .{ .name = "inventory", .module = inventory_mod },
                .{ .name = "enemies", .module = enemies_mod },
                .{ .name = "mission", .module = mission_mod },
                .{ .name = "wiring", .module = wiring_mod },
                .{ .name = "proven_bridge", .module = proven_bridge_mod },
                .{ .name = "multiplayer", .module = multiplayer_mod },
                .{ .name = "game_systems", .module = game_systems_mod },
            },
        }),
    });

    const run_tests = b.addRunArtifact(integration_tests);
    const test_step = b.step("test", "Run IDApTIK UMS FFI integration tests");
    test_step.dependOn(&run_tests.step);
}
