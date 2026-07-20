// SPDX-License-Identifier: MPL-2.0
// multiplayer.zig -- FFI operations for asymmetric co-op multiplayer.
// Author: Jonathan D.A. Jewell
//
// Companion to Multiplayer.idr.  Provides C-ABI types and functions for:
//   - Player role validation and encoding
//   - Session phase transitions
//   - Alert level comparison (total order)
//   - Sync message kind classification
//   - Player list management
//
// These types are used by the Gossamer IPC layer and the ReScript
// MultiplayerClient to ensure type-safe communication with the sync server.

const std = @import("std");

// =========================================================================
// Types (mirrors Multiplayer.idr)
// =========================================================================

/// Player role in asymmetric co-op.
/// Mirrors `Multiplayer.CoopRole`.
pub const CoopRole = enum(u8) {
    jessica = 0,
    q_hacker = 1,
    observer = 2,
};

/// Multiplayer connection state.
/// Mirrors `Multiplayer.ConnectionState`.
pub const ConnectionState = enum(u8) {
    offline = 0,
    connecting = 1,
    in_lobby = 2,
    in_session = 3,
};

/// Game session phase (mirrors GameStateMachine).
/// Mirrors `Multiplayer.SessionPhase`.
pub const SessionPhase = enum(u8) {
    lobby = 0,
    countdown = 1,
    loading = 2,
    playing = 3,
    paused = 4,
    complete = 5,
};

/// Facility-wide alert level with total ordering.
/// Mirrors `Multiplayer.MultiplayerAlert`.
pub const AlertLevel = enum(u8) {
    green = 0,
    yellow = 1,
    orange = 2,
    red = 3,
};

/// Sync message kinds.
/// Mirrors `Multiplayer.SyncMessageKind`.
pub const SyncMessageKind = enum(u8) {
    position = 0,
    vm_execute = 1,
    vm_undo = 2,
    vm_state = 3,
    bebop_discovered = 4,
    bebop_activated = 5,
    bebop_coop_req = 6,
    bebop_coop_accept = 7,
    device_accessed = 8,
    alert_changed = 9,
    chat = 10,
};

/// A player in a multiplayer session.
/// Mirrors `Multiplayer.PlayerInfo`.
pub const PlayerInfo = extern struct {
    player_id: ?[*:0]const u8,
    role: CoopRole,
    _pad0: u8 = 0,
    _pad1: u8 = 0,
    _pad2: u8 = 0,
    _pad3: u8 = 0,
    _pad4: u8 = 0,
    _pad5: u8 = 0,
    _pad6: u8 = 0,
    pos_x: f64,
    pos_y: f64,
};

/// A chat message.
/// Mirrors `Multiplayer.ChatMessage`.
pub const ChatMessage = extern struct {
    sender_id: ?[*:0]const u8,
    content: ?[*:0]const u8,
    timestamp: f64,
};

/// Maximum players in a session (2 primary + observers).
pub const MAX_PLAYERS: usize = 8;

/// Session state for C ABI consumers.
pub const SessionState = extern struct {
    session_id: ?[*:0]const u8,
    phase: SessionPhase,
    alert: AlertLevel,
    _pad0: u8 = 0,
    _pad1: u8 = 0,
    players: [MAX_PLAYERS]PlayerInfo,
    players_len: u32,
};

// =========================================================================
// Role validation
// =========================================================================

/// Check if two roles are different (asymmetric co-op requirement).
/// Materialises the Idris2 disjointness proofs at runtime.
pub export fn idaptik_mp_roles_disjoint(role_a: u8, role_b: u8) callconv(.c) bool {
    return role_a != role_b;
}

/// Validate a role value is in range.
pub export fn idaptik_mp_valid_role(role: u8) callconv(.c) bool {
    return role <= 2;
}

// =========================================================================
// Alert level operations
// =========================================================================

/// Compare two alert levels (total order).
/// Returns true if a <= b.
pub export fn idaptik_mp_alert_lte(a: u8, b: u8) callconv(.c) bool {
    return a <= b;
}

/// Get the maximum (most severe) of two alert levels.
pub export fn idaptik_mp_alert_max(a: u8, b: u8) callconv(.c) u8 {
    return if (a > b) a else b;
}

/// Escalate an alert level by one step (green→yellow→orange→red).
/// Returns the current level if already red.
pub export fn idaptik_mp_alert_escalate(current: u8) callconv(.c) u8 {
    if (current >= @intFromEnum(AlertLevel.red)) return current;
    return current + 1;
}

// =========================================================================
// Session management
// =========================================================================

/// Add a player to a session.
/// Returns true on success, false if at capacity or null pointer.
pub export fn idaptik_mp_add_player(
    session: ?*SessionState,
    player: ?*const PlayerInfo,
) callconv(.c) bool {
    const s = session orelse return false;
    const p = player orelse return false;
    if (s.players_len >= MAX_PLAYERS) return false;
    s.players[s.players_len] = p.*;
    s.players_len += 1;
    return true;
}

/// Count players with a specific role.
pub export fn idaptik_mp_count_role(
    session: ?*const SessionState,
    role: u8,
) callconv(.c) u32 {
    const s = session orelse return 0;
    const target: CoopRole = @enumFromInt(role);
    var count: u32 = 0;
    for (s.players[0..s.players_len]) |p| {
        if (p.role == target) count += 1;
    }
    return count;
}

/// Validate session has required roles (at least one Jessica + one Q).
/// Returns true if the session can start.
pub export fn idaptik_mp_can_start(
    session: ?*const SessionState,
) callconv(.c) bool {
    const s = session orelse return false;
    var has_jessica = false;
    var has_q = false;
    for (s.players[0..s.players_len]) |p| {
        switch (p.role) {
            .jessica => has_jessica = true,
            .q_hacker => has_q = true,
            .observer => {},
        }
    }
    return has_jessica and has_q;
}

/// Validate a phase transition is legal.
/// Returns true if transitioning from `current` to `next` is allowed.
pub export fn idaptik_mp_valid_transition(current: u8, next: u8) callconv(.c) bool {
    // Legal transitions:
    //   lobby → countdown (all ready)
    //   countdown → loading (timer expired)
    //   loading → playing (assets loaded)
    //   playing → paused (any player pauses)
    //   playing → complete (game ends)
    //   paused → playing (resume)
    //   paused → complete (quit during pause)
    return switch (current) {
        0 => next == 1, // lobby → countdown
        1 => next == 2, // countdown → loading
        2 => next == 3, // loading → playing
        3 => next == 4 or next == 5, // playing → paused or complete
        4 => next == 3 or next == 5, // paused → playing or complete
        else => false,
    };
}

// =========================================================================
// Tests
// =========================================================================

test "roles disjoint" {
    try std.testing.expect(idaptik_mp_roles_disjoint(0, 1));
    try std.testing.expect(idaptik_mp_roles_disjoint(0, 2));
    try std.testing.expect(idaptik_mp_roles_disjoint(1, 2));
    try std.testing.expect(!idaptik_mp_roles_disjoint(0, 0));
}

test "alert ordering" {
    try std.testing.expect(idaptik_mp_alert_lte(0, 3)); // green <= red
    try std.testing.expect(!idaptik_mp_alert_lte(3, 0)); // red > green
    try std.testing.expectEqual(@as(u8, 3), idaptik_mp_alert_max(1, 3));
    try std.testing.expectEqual(@as(u8, 1), idaptik_mp_alert_escalate(0)); // green → yellow
    try std.testing.expectEqual(@as(u8, 3), idaptik_mp_alert_escalate(3)); // red stays red
}

test "session can start" {
    var session = std.mem.zeroes(SessionState);

    // No players — cannot start.
    try std.testing.expect(!idaptik_mp_can_start(&session));

    // Add Jessica.
    const jessica = PlayerInfo{
        .player_id = null,
        .role = .jessica,
        .pos_x = 0.0,
        .pos_y = 0.0,
    };
    try std.testing.expect(idaptik_mp_add_player(&session, &jessica));
    try std.testing.expect(!idaptik_mp_can_start(&session)); // Still need Q.

    // Add Q.
    const q = PlayerInfo{
        .player_id = null,
        .role = .q_hacker,
        .pos_x = 0.0,
        .pos_y = 0.0,
    };
    try std.testing.expect(idaptik_mp_add_player(&session, &q));
    try std.testing.expect(idaptik_mp_can_start(&session)); // Now valid.
}

test "valid phase transitions" {
    try std.testing.expect(idaptik_mp_valid_transition(0, 1)); // lobby → countdown
    try std.testing.expect(idaptik_mp_valid_transition(3, 4)); // playing → paused
    try std.testing.expect(idaptik_mp_valid_transition(4, 3)); // paused → playing
    try std.testing.expect(!idaptik_mp_valid_transition(0, 3)); // lobby → playing (illegal)
    try std.testing.expect(!idaptik_mp_valid_transition(5, 0)); // complete → lobby (illegal)
}
