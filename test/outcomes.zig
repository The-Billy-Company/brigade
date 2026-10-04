//! Real adverse outcomes: a leak must fail its run without contaminating the
//! following clean test, and errors and skips must retain their own counts.

const std = @import("std");

test "runner-leak" {
    const leaked = try std.testing.allocator.alloc(u8, 8);
    @memset(leaked, 0);
}

test "runner-clean-after-leak" {
    const scratch = try std.testing.allocator.alloc(u8, 8);
    defer std.testing.allocator.free(scratch);
    @memset(scratch, 0);
    try std.testing.expectEqual(@as(u8, 0), scratch[0]);
}

test "runner-error" {
    return error.DeliberateFailure;
}

test "runner-logged-error" {
    std.log.err("deliberate logged failure", .{});
}

test "runner-skip" {
    return error.SkipZigTest;
}
