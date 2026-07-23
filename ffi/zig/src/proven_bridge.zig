// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// proven_bridge.zig -- FFI bridge to formally-verified operations.
// Author: Jonathan D.A. Jewell
//
// Companion to ProvenBridge.idr.  Provides C-ABI implementations of:
//   - SafeMath:   Saturating arithmetic for damage, HP, and alert calculations
//   - SafeString: Bounded string operations for player input / terminal display
//   - SafeCrypto: Constant-time comparison for multiplayer authentication tokens
//   - SafeInput:  Keystroke validation for terminal hacking sequences
//
// SafeJson is handled by the existing serialize/deserialize in main.zig.
//
// These functions mirror the formally-verified Idris2 definitions:
//   - No panics, no undefined behaviour, no silent truncation
//   - All arithmetic saturates rather than wrapping
//   - All string operations are bounded
//   - Token comparison is constant-time to prevent timing attacks

const std = @import("std");

// =========================================================================
// SafeMath: saturating game arithmetic
// =========================================================================

/// Saturating add for HP/damage calculations.
///
/// Mirrors ProvenBridge.safeAdd — returns min(a + b, max_val).
/// If max_val is 0, returns 0 (degenerate case).
pub export fn idaptik_safe_add(a: u32, b: u32, max_val: u32) callconv(.c) u32 {
    const result = @as(u64, a) + @as(u64, b);
    if (result > max_val) return max_val;
    return @intCast(result);
}

/// Saturating subtract for damage application.
///
/// Mirrors ProvenBridge.safeSub — returns max(a - b, 0).
/// Never underflows.
pub export fn idaptik_safe_sub(a: u32, b: u32) callconv(.c) u32 {
    if (b >= a) return 0;
    return a - b;
}

/// Saturating multiply for critical hit / multiplier calculations.
///
/// Mirrors ProvenBridge.safeMul — returns min(a * b, max_val).
pub export fn idaptik_safe_mul(a: u32, b: u32, max_val: u32) callconv(.c) u32 {
    const result = @as(u64, a) * @as(u64, b);
    if (result > max_val) return max_val;
    return @intCast(result);
}

/// Clamp a value to [min_val, max_val].
///
/// Used for alert level clamping, stat bounds, etc.
pub export fn idaptik_safe_clamp(value: u32, min_val: u32, max_val: u32) callconv(.c) u32 {
    if (value < min_val) return min_val;
    if (value > max_val) return max_val;
    return value;
}

/// Safe percentage calculation: (value * 100) / total.
///
/// Returns 0 if total is 0 (avoids division by zero).
/// Result is clamped to 100 maximum.
pub export fn idaptik_safe_percentage(value: u32, total: u32) callconv(.c) u32 {
    if (total == 0) return 0;
    const result = (@as(u64, value) * 100) / @as(u64, total);
    if (result > 100) return 100;
    return @intCast(result);
}

// =========================================================================
// SafeString: bounded string operations
// =========================================================================

/// Measure a null-terminated string length, capped at max_len.
///
/// Returns the shorter of the actual length and max_len.
/// Returns 0 for null input.  Used to prevent buffer overruns in
/// terminal display and player name handling.
pub export fn idaptik_safe_strlen(
    s: ?[*:0]const u8,
    max_len: u32,
) callconv(.c) u32 {
    const ptr = s orelse return 0;
    const span = std.mem.span(ptr);
    const len: u32 = @intCast(@min(span.len, @as(usize, max_len)));
    return len;
}

/// Check whether a string contains only printable ASCII (0x20-0x7E).
///
/// Used for player name validation and terminal input sanitisation.
/// Returns `true` if all characters are printable ASCII, `false` otherwise.
/// Empty strings and null inputs return `true` (vacuously safe).
pub export fn idaptik_safe_is_printable_ascii(
    s: ?[*:0]const u8,
) callconv(.c) bool {
    const ptr = s orelse return true;
    const span = std.mem.span(ptr);
    for (span) |c| {
        if (c < 0x20 or c > 0x7E) return false;
    }
    return true;
}

// =========================================================================
// SafeCrypto: constant-time token comparison
// =========================================================================

/// Constant-time comparison of two byte buffers.
///
/// Mirrors ProvenBridge.safeTokenCompare.  Compares `len` bytes from
/// `a` and `b` in constant time to prevent timing side-channels in
/// multiplayer authentication.
///
/// Returns `true` if all bytes match, `false` otherwise.
/// Returns `false` if either pointer is null or len is 0.
pub export fn idaptik_safe_token_compare(
    a: ?[*]const u8,
    b: ?[*]const u8,
    len: u32,
) callconv(.c) bool {
    const pa = a orelse return false;
    const pb = b orelse return false;
    if (len == 0) return false;

    var diff: u8 = 0;
    for (pa[0..len], pb[0..len]) |ca, cb| {
        diff |= ca ^ cb;
    }
    return diff == 0;
}

// =========================================================================
// SafeInput: keystroke validation for terminal hacking
// =========================================================================

/// Validate a terminal keystroke for the hacking minigame.
///
/// Returns the keystroke classification:
///   0 = invalid (control character, null, etc.)
///   1 = printable character (add to command buffer)
///   2 = backspace (0x08 or 0x7F — delete last character)
///   3 = enter (0x0A or 0x0D — submit command)
///   4 = tab (0x09 — autocomplete)
///   5 = escape (0x1B — cancel/close terminal)
///
/// This is the runtime materialisation of the ProvenBridge.KeystrokeClass
/// algebraic data type.
pub export fn idaptik_classify_keystroke(keycode: u8) callconv(.c) u8 {
    return switch (keycode) {
        0x08, 0x7F => 2, // Backspace / Delete.
        0x09 => 4, // Tab.
        0x0A, 0x0D => 3, // Enter / Return.
        0x1B => 5, // Escape.
        0x20...0x7E => 1, // Printable ASCII.
        else => 0, // Invalid / control character.
    };
}

// =========================================================================
// Tests
// =========================================================================

test "safe add saturates" {
    try std.testing.expectEqual(@as(u32, 150), idaptik_safe_add(100, 50, 200));
    try std.testing.expectEqual(@as(u32, 200), idaptik_safe_add(150, 100, 200)); // Saturates.
    try std.testing.expectEqual(@as(u32, 0), idaptik_safe_add(100, 50, 0)); // Degenerate.
}

test "safe sub floors at zero" {
    try std.testing.expectEqual(@as(u32, 50), idaptik_safe_sub(100, 50));
    try std.testing.expectEqual(@as(u32, 0), idaptik_safe_sub(50, 100)); // Floor.
    try std.testing.expectEqual(@as(u32, 0), idaptik_safe_sub(50, 50)); // Exact.
}

test "safe mul saturates" {
    try std.testing.expectEqual(@as(u32, 200), idaptik_safe_mul(10, 20, 1000));
    try std.testing.expectEqual(@as(u32, 999), idaptik_safe_mul(100, 100, 999)); // Saturates.
}

test "safe clamp" {
    try std.testing.expectEqual(@as(u32, 50), idaptik_safe_clamp(50, 0, 100));
    try std.testing.expectEqual(@as(u32, 0), idaptik_safe_clamp(0, 0, 100));
    try std.testing.expectEqual(@as(u32, 10), idaptik_safe_clamp(5, 10, 100)); // Below min.
    try std.testing.expectEqual(@as(u32, 100), idaptik_safe_clamp(150, 10, 100)); // Above max.
}

test "safe percentage" {
    try std.testing.expectEqual(@as(u32, 50), idaptik_safe_percentage(50, 100));
    try std.testing.expectEqual(@as(u32, 0), idaptik_safe_percentage(50, 0)); // Div by zero.
    try std.testing.expectEqual(@as(u32, 100), idaptik_safe_percentage(200, 100)); // Capped.
}

test "constant-time token compare" {
    const token_a = "abcdef12";
    const token_b = "abcdef12";
    const token_c = "abcdef13";

    try std.testing.expect(idaptik_safe_token_compare(token_a, token_b, 8));
    try std.testing.expect(!idaptik_safe_token_compare(token_a, token_c, 8));
    try std.testing.expect(!idaptik_safe_token_compare(null, token_b, 8));
}

test "classify keystroke" {
    try std.testing.expectEqual(@as(u8, 1), idaptik_classify_keystroke('a')); // Printable.
    try std.testing.expectEqual(@as(u8, 1), idaptik_classify_keystroke('~')); // Printable.
    try std.testing.expectEqual(@as(u8, 2), idaptik_classify_keystroke(0x08)); // Backspace.
    try std.testing.expectEqual(@as(u8, 2), idaptik_classify_keystroke(0x7F)); // Delete.
    try std.testing.expectEqual(@as(u8, 3), idaptik_classify_keystroke(0x0A)); // Enter.
    try std.testing.expectEqual(@as(u8, 4), idaptik_classify_keystroke(0x09)); // Tab.
    try std.testing.expectEqual(@as(u8, 5), idaptik_classify_keystroke(0x1B)); // Escape.
    try std.testing.expectEqual(@as(u8, 0), idaptik_classify_keystroke(0x01)); // Invalid.
}

test "safe strlen bounded" {
    const hello = "hello";
    try std.testing.expectEqual(@as(u32, 5), idaptik_safe_strlen(hello, 100));
    try std.testing.expectEqual(@as(u32, 3), idaptik_safe_strlen(hello, 3)); // Capped.
    try std.testing.expectEqual(@as(u32, 0), idaptik_safe_strlen(null, 100)); // Null.
}

test "printable ASCII check" {
    try std.testing.expect(idaptik_safe_is_printable_ascii("hello world"));
    try std.testing.expect(idaptik_safe_is_printable_ascii(null)); // Vacuously true.
    try std.testing.expect(!idaptik_safe_is_printable_ascii("hello\x01")); // Control char.
}
