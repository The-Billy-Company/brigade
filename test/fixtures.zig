//! A corpus with exactly one property: twelve tests, declared in a known
//! order, each of which does nothing and cannot fail.
//!
//! `build.zig`'s `partition` runs the real runner over this and checks the
//! summary against counts worked out from the residue contract by hand. That
//! only proves anything if the corpus itself is inert — a fixture that could
//! fail, leak, or skip would let a wrong partition and a broken test cancel
//! out into a plausible-looking number.
//!
//! The `even`/`odd` tags are the narrowing oracle: six names contain `even`,
//! six contain `odd`, and every name contains `fixture`. Do not renumber or
//! retag without updating the expected counts in `build.zig`.

const std = @import("std");

/// Touch the allocator so a fixture is not so empty the compiler can elide the
/// per-test setup brigade is being measured on. Also makes a leak-detection
/// regression visible here rather than only in a consumer's suite.
fn inert() !void {
    const scratch = try std.testing.allocator.alloc(u8, 8);
    defer std.testing.allocator.free(scratch);
    @memset(scratch, 0);
}

test "fixture even 00" {
    try inert();
}
test "fixture odd 01" {
    try inert();
}
test "fixture even 02" {
    try inert();
}
test "fixture odd 03" {
    try inert();
}
test "fixture even 04" {
    try inert();
}
test "fixture odd 05" {
    try inert();
}
test "fixture even 06" {
    try inert();
}
test "fixture odd 07" {
    try inert();
}
test "fixture even 08" {
    try inert();
}
test "fixture odd 09" {
    try inert();
}
test "fixture even 10" {
    try inert();
}
test "fixture odd 11" {
    try inert();
}
