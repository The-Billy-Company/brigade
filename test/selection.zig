//! The algebra brigade rests on: which process claims which test, and which
//! names a run admits.
//!
//! Every expectation here is derived from the stated contract — "a process
//! claims the residues i, i+n, i+2n, …", "the same substring match shape as
//! `zig test --test-filter`" — not from what the code happens to return. The
//! partition property in particular is checked exhaustively rather than
//! sampled: a runner that drops one test in a rare shard configuration reports
//! a green suite that didn't run it, which is the one failure mode a test
//! runner must not have.

const std = @import("std");

/// The runner is this binary's root module — the same door a consumer's test
/// reaches `note` through, and the only one available here: a file cannot be
/// both a compilation's test runner and one of its imported modules. Testing
/// through the real access path rather than a second module instance is the
/// better bargain anyway.
const brigade = @import("root");

const Shard = brigade.Shard;
const Patterns = brigade.Patterns;

// -- BRIGADE_SHARD parsing ---------------------------------------------------

test "a well-formed spec parses to its two numbers" {
    const s = Shard.parse("3/8").?;
    try std.testing.expectEqual(@as(usize, 3), s.index);
    try std.testing.expectEqual(@as(usize, 8), s.count);
}

test "the last valid index of a count is index = count - 1" {
    const s = Shard.parse("7/8").?;
    try std.testing.expectEqual(@as(usize, 7), s.index);
    try std.testing.expectEqual(@as(usize, 8), s.count);
}

test "a malformed spec is refused rather than defaulted" {
    // Each of these would, if silently coerced to a default, produce a process
    // that owns the wrong subset and still exits 0.
    const refused = [_][]const u8{
        "", // nothing at all
        "1", // no separator
        "/", // separators but no numbers
        "1/", // no count
        "/2", // no index
        "0/0", // a count of zero owns nothing, forever
        "2/2", // index == count: one past the last valid shard
        "9/2", // index > count
        "x/2", // non-numeric index
        "0/y", // non-numeric count
        "-1/2", // negative index (usize parse refuses the sign)
        "1 / 2", // spaces are not trimmed; a shell quoting slip is not a guess
        "1/2/3", // trailing garbage the count parse must reject
    };
    for (refused) |spec| {
        try std.testing.expectEqual(@as(?Shard, null), Shard.parse(spec));
    }
}

test "an unset environment behaves exactly like the stock runner" {
    // The default Shard is the whole suite in one process — the property that
    // lets brigade be dropped in without any build change taking effect yet.
    const all: Shard = .{};
    try std.testing.expectEqual(@as(usize, 1), all.count);
    for (0..64) |i| try std.testing.expect(all.owns(i));
}

// -- the partition property --------------------------------------------------

test "every test is owned by exactly one shard, for every shard count" {
    // The whole correctness claim, checked rather than argued: over shard
    // counts 1..=32 and 256 test positions, each position is claimed once.
    // Exhaustive because the failure it guards against — a position no shard
    // claims — is invisible in a green run.
    for (1..33) |count| {
        for (0..256) |position| {
            var owners: usize = 0;
            for (0..count) |index| {
                const shard: Shard = .{ .index = index, .count = count };
                owners += @intFromBool(shard.owns(position));
            }
            try std.testing.expectEqual(@as(usize, 1), owners);
        }
    }
}

test "a shard claims a stride, not a contiguous block" {
    // Cost clusters by module because tests are declared in module order, so a
    // contiguous split hands one shard every expensive test in a file.
    // Striding is what spreads a cluster; assert the stride, not just coverage.
    const shard: Shard = .{ .index = 1, .count = 4 };
    const claimed = [_]usize{ 1, 5, 9, 13, 17 };
    for (claimed) |position| try std.testing.expect(shard.owns(position));
    for ([_]usize{ 0, 2, 3, 4, 6, 7, 8 }) |position| try std.testing.expect(!shard.owns(position));
}

test "more shards than tests leaves the tail owning nothing" {
    // Not an error: `zig build test` on a 4-test package with 32 cores asks
    // for 64 shards, and 60 of them are correctly empty.
    var claimed: usize = 0;
    for (0..64) |index| {
        const shard: Shard = .{ .index = index, .count = 64 };
        for (0..4) |position| claimed += @intFromBool(shard.owns(position));
    }
    try std.testing.expectEqual(@as(usize, 4), claimed);
}

// -- BRIGADE_FILTER / BRIGADE_SKIP -------------------------------------------

test "a pattern matches anywhere in the name, like --test-filter" {
    const p: Patterns = .{ .spec = "walk" };
    try std.testing.expect(p.matches("corpus.test.walk prunes ignored dirs"));
    try std.testing.expect(p.matches("walk"));
    try std.testing.expect(!p.matches("corpus.test.scan"));
}

test "a name copied out of a FAIL line is a valid pattern" {
    // The property that makes the failure message actionable: brigade prints
    // the full test name, and that string fed back as a filter selects it.
    const name = "regex.test.onepass differential over the pattern corpus";
    try std.testing.expect((Patterns{ .spec = name }).matches(name));
}

test "commas separate alternatives and any one of them selects" {
    const p: Patterns = .{ .spec = "alpha,beta,gamma" };
    try std.testing.expect(p.matches("x.test.beta rises"));
    try std.testing.expect(p.matches("x.test.gamma falls"));
    try std.testing.expect(!p.matches("x.test.delta holds"));
}

test "empty entries are ignored, so a stray comma matches nothing extra" {
    // An exported-but-empty variable and a trailing comma are the two ways a
    // shell hands over a spec with a hole in it. Treating "" as a substring
    // would match every test — a filter that selects everything and a skip
    // that stands everything aside are both silent disasters.
    for ([_][]const u8{ "", ",", ",,", "alpha,", ",alpha" }) |spec| {
        const p: Patterns = .{ .spec = spec };
        try std.testing.expect(!p.matches("x.test.zeta"));
    }
    try std.testing.expect((Patterns{ .spec = "alpha," }).matches("x.test.alpha"));
}

test "filter admits, skip rejects, and skip wins when both match" {
    const alpha: Patterns = .{ .spec = "alpha" };
    const slow: Patterns = .{ .spec = "slow" };

    // Neither set: everything runs. This is the unset-environment path.
    try std.testing.expect(brigade.selects(null, null, "x.test.anything"));

    // Filter alone.
    try std.testing.expect(brigade.selects(alpha, null, "x.test.alpha rises"));
    try std.testing.expect(!brigade.selects(alpha, null, "x.test.beta rises"));

    // Skip alone.
    try std.testing.expect(!brigade.selects(null, slow, "x.test.slow differential"));
    try std.testing.expect(brigade.selects(null, slow, "x.test.quick check"));

    // Both, disjoint: the filter's set minus the skip's.
    try std.testing.expect(brigade.selects(alpha, slow, "x.test.alpha quick"));
    try std.testing.expect(!brigade.selects(alpha, slow, "x.test.beta quick"));

    // Both, overlapping: skip wins. A quick tier that names a long pole in
    // BRIGADE_SKIP must stand it aside even when the user's filter selected
    // it — otherwise `test-quick -Dtest-filter=<long pole>` is not quick.
    try std.testing.expect(!brigade.selects(alpha, slow, "x.test.alpha slow differential"));
}

test "selection is total: every name is either selected or not, never both" {
    // Guards the shape of `selects` itself — the count of selected tests is
    // what the summary reports as the denominator, so a name that both passes
    // and fails selection would make that number meaningless.
    const filter: Patterns = .{ .spec = "e" };
    const skip: Patterns = .{ .spec = "s" };
    const names = [_][]const u8{ "even", "odds", "eels", "zzz", "", "es" };
    for (names) |name| {
        const admitted = brigade.selects(filter, skip, name);
        const by_hand = std.mem.indexOf(u8, name, "e") != null and
            std.mem.indexOf(u8, name, "s") == null;
        try std.testing.expectEqual(by_hand, admitted);
    }
}

test "narrowing composes with sharding: a filtered run still splits" {
    // Filter and skip are applied *before* the residue test, so the positions
    // handed to `owns` are indices into the selected set, not the full suite.
    // That is what keeps a narrowed run parallel instead of collapsing onto
    // whichever shard happened to hold the surviving tests.
    const filter: Patterns = .{ .spec = "keep" };
    const names = [_][]const u8{
        "keep 0", "drop a", "keep 1", "drop b", "keep 2", "drop c", "keep 3",
    };

    var claimed: [2]usize = .{ 0, 0 };
    for (0..2) |index| {
        const shard: Shard = .{ .index = index, .count = 2 };
        var position: usize = 0;
        for (names) |name| {
            if (!brigade.selects(filter, null, name)) continue;
            defer position += 1;
            if (shard.owns(position)) claimed[index] += 1;
        }
    }
    // Four selected, split 2/2 — not 4/0, which is what indexing into the full
    // suite would produce here.
    try std.testing.expectEqual([2]usize{ 2, 2 }, claimed);
}
