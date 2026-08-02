//! The build-side half of brigade: the shard fan-out, and the three `-D`
//! options that steer it.
//!
//! `brigade.zig` decides which tests a *process* owns. Nothing in it creates
//! parallelism — that is this file's job, and it does it by hanging n
//! independent `Run` steps off one compiled test binary and letting Zig's own
//! build runner schedule them. Every consumer used to restate that loop, the
//! `2x cores` default, and the option triple in its own `build.zig`; they are
//! stated once here.
//!
//! ```zig
//! const brigade = @import("brigade");
//!
//! pub fn build(b: *std.Build) void {
//!     const bg = brigade.init(b, .{});
//!     const tests = b.addTest(.{ .root_module = m, .test_runner = bg.runner() });
//!
//!     bg.shard(b.step("test", "Run unit tests"), tests, .{});
//!     bg.shard(b.step("test-quick", "the same minus the long poles"), tests, .{ .skip = &deep });
//! }
//! ```

const std = @import("std");

/// The most shards worth asking for. Past this the build runner's scheduling
/// overhead outweighs a finer split, and a machine reporting an absurd core
/// count (a container inheriting the host's) can't fork-bomb the build.
const max_shards = 64;

pub const Options = struct {
    /// Default shard count. Null asks for **2x** the CPU count (capped at
    /// `max_shards`), not 1x: the build runner keeps only `cores - 1` steps in
    /// flight, so over-decomposing turns its scheduler into the work queue a
    /// static split otherwise lacks — a shard that drew a cheap slice ends and
    /// the next starts, rather than a core idling beside a grinding neighbor.
    /// `-Dtest-shards=` overrides it per-run either way.
    shards: ?usize = null,
    /// Where `brigade.zig` lives. Null resolves it out of this package
    /// wherever it was fetched to, by asking `b`'s own manifest — which is
    /// right whenever `b` is the builder that declared `.brigade`.
    ///
    /// Pass a path in the two cases where it isn't:
    ///
    /// - **brigade's own build**, since a package is not a dependency of
    ///   itself;
    /// - **a build helper standing between brigade and the root build** — a
    ///   shared chassis that declares `.brigade` and is handed a *consumer's*
    ///   `b` to attach steps to. That `b`'s manifest names the chassis, not
    ///   brigade. The helper reaches its own dependency table through its own
    ///   `Dependency`:
    ///
    ///   ```zig
    ///   const self = b.dependencyFromBuildZig(@This(), .{});
    ///   const bg = brigade.init(b, .{ .source = self.builder.dependency("brigade", .{}).path("brigade.zig") });
    ///   ```
    source: ?std.Build.LazyPath = null,
};

/// Extra narrowing for one step, on top of whatever `-Dtest-filter` /
/// `-Dtest-skip` the caller passed.
pub const Shards = struct {
    /// Processes to split across. Null uses the build-wide count; `1` is the
    /// single-process run a debugger, a bisect, or a coverage pass needs.
    count: ?usize = null,
    /// Name substrings this step stands aside, unioned with `-Dtest-skip`.
    /// This is how a `test-quick` tier is spelled: name the measured long
    /// poles and the step runs everything else. A pattern that matches no test
    /// is reported by name — it can only ever make the tier slower, never less
    /// safe, but silent drift is still drift.
    skip: []const []const u8 = &.{},
};

/// Read the option triple and locate the runner. **Call once per build** —
/// `b.option` refuses a duplicate name, which is the right failure for a
/// second call but an opaque one, so hold the returned handle rather than
/// re-initializing.
pub fn init(b: *std.Build, opts: Options) Brigade {
    return .{
        .b = b,
        .source = opts.source orelse b.dependencyFromBuildZig(@This(), .{}).path("brigade.zig"),
        .shards = b.option(
            usize,
            "test-shards",
            "how many parallel processes `zig build test` splits the unit-test binary across (default: 2x CPU count; 1 restores a single-process run)",
        ) orelse opts.shards orelse defaultShards(),
        .filter = b.option(
            []const u8,
            "test-filter",
            "run only unit tests whose name contains one of these comma-separated substrings",
        ),
        .skip = b.option(
            []const u8,
            "test-skip",
            "skip unit tests whose name contains one of these comma-separated substrings",
        ),
    };
}

fn defaultShards() usize {
    return @min(@max(std.Thread.getCpuCount() catch 1, 1) * 2, max_shards);
}

pub const Brigade = struct {
    b: *std.Build,
    source: std.Build.LazyPath,
    /// Resolved shard count for a step that doesn't override it.
    shards: usize,
    /// `-Dtest-filter`, verbatim. Null means the run was not narrowed.
    filter: ?[]const u8,
    /// `-Dtest-skip`, verbatim.
    skip: ?[]const u8,

    /// Hand to `b.addTest(.{ .test_runner = ... })`. `.simple` mode is not a
    /// preference: the `std.zig.Server` protocol hands out one test index at a
    /// time and awaits its result, so it cannot express a parallel run. Simple
    /// mode judges a shard by its exit code, which can.
    pub fn runner(bg: Brigade) std.Build.Step.Compile.TestRunner {
        return .{ .path = bg.source, .mode = .simple };
    }

    /// Fan `tests` out across processes and make `step` depend on all of them.
    ///
    /// The same compiled binary backs every shard — one compile, n runs — so a
    /// second step over the same `tests` (a quick tier, an unsharded variant)
    /// costs only its own processes. Each shard's environment is part of its
    /// cache key, so an unchanged tree replays a proven-green shard instead of
    /// re-running it, and only a success is ever recorded.
    pub fn shard(bg: Brigade, step: *std.Build.Step, tests: *std.Build.Step.Compile, opts: Shards) void {
        const count = opts.count orelse bg.shards;
        const skip = bg.skipSpec(opts.skip);
        for (0..count) |i| {
            const run = bg.b.addRunArtifact(tests);
            run.setEnvironmentVariable("BRIGADE_SHARD", bg.b.fmt("{d}/{d}", .{ i, count }));
            if (bg.filter) |f| run.setEnvironmentVariable("BRIGADE_FILTER", f);
            if (skip) |s| run.setEnvironmentVariable("BRIGADE_SKIP", s);
            run.expectExitCode(0);
            run.setName(bg.b.fmt("{s} shard {d}/{d}", .{ step.name, i, count }));
            step.dependOn(&run.step);
        }
    }

    /// Pin an already-built `Run` to a single process owning every test — for
    /// a wrapper brigade can't fan out, like `kcov` over the test artifact,
    /// where n processes would each write a partial profile.
    pub fn whole(bg: Brigade, run: *std.Build.Step.Run) void {
        run.setEnvironmentVariable("BRIGADE_SHARD", "0/1");
        if (bg.filter) |f| run.setEnvironmentVariable("BRIGADE_FILTER", f);
        if (bg.skipSpec(&.{})) |s| run.setEnvironmentVariable("BRIGADE_SKIP", s);
    }

    /// Did `-Dtest-filter` narrow this run? A build that folds a *second* test
    /// binary into `test` has to ask: brigade fails a shard whose filter
    /// matched none of its tests — correct for one binary (you typo'd it),
    /// wrong across two, where a name living in the other binary is not a typo.
    /// So fold the extra binary in only on an unfiltered run, and let a
    /// filtered hunt name the binary it is hunting in.
    pub fn narrowed(bg: Brigade) bool {
        return bg.filter != null;
    }

    /// `-Dtest-skip` unioned with a step's own patterns, or null when both are
    /// empty. Comma-joined because that is the spec `BRIGADE_SKIP` parses.
    fn skipSpec(bg: Brigade, extra: []const []const u8) ?[]const u8 {
        var spec = bg.skip;
        for (extra) |pattern| spec = if (spec) |s| bg.b.fmt("{s},{s}", .{ s, pattern }) else pattern;
        return spec;
    }
};

// -- brigade's own suite ----------------------------------------------------
//
// Two layers, because the two halves fail differently. `test/selection.zig`
// proves the residue and pattern algebra in-process; `test/fixtures.zig` is a
// corpus of deterministically-named no-op tests that the *real* runner is
// pointed at from outside, so the partition claim is checked against a count
// worked out from the contract rather than reported by the code under test.

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bg = init(b, .{ .source = b.path("brigade.zig") });

    // No `brigade` module import: the runner already *is* this binary's root,
    // and a file cannot belong to two modules of one compilation. The suite
    // reaches it as `@import("root")`, which is also how a consumer's test
    // reaches `note` — so the access path under test is the shipped one.
    const selection = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/selection.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .test_runner = bg.runner(),
    });

    const test_step = b.step("test", "Run brigade's own suite (self-hosted: brigade runs it)");
    bg.shard(test_step, selection, .{});
    partition(b, target, optimize, bg, test_step);

    b.step("check", "Compile the suite without running it (--watch / ZLS loop)")
        .dependOn(&selection.step);
}

/// Point the real runner at a 12-test corpus and check what each spelling
/// claims. Expected counts come from the residue contract — the size of
/// `{k < 12 : k = i (mod n)}` — worked out here, not observed from a run.
fn partition(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    bg: Brigade,
    test_step: *std.Build.Step,
) void {
    const fixtures = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/fixtures.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .test_runner = bg.runner(),
    });

    // Spec, and how many of the 12 fixtures that residue class claims. The
    // fan-out below is deliberately NOT `bg.shard` — these counts are the
    // thing under test, so `-Dtest-shards` must not reach them.
    const claims = .{
        .{ "0/1", 12 }, // one process owns every residue
        .{ "0/2", 6 }, // evens
        .{ "1/2", 6 }, // odds
        .{ "0/4", 3 }, // {0,4,8}
        .{ "3/4", 3 }, // {3,7,11}
        .{ "0/5", 3 }, // {0,5,10} -- an uneven split, deliberately
        .{ "2/5", 2 }, // {2,7}
        .{ "4/5", 2 }, // {4,9}
        .{ "0/16", 1 }, // more shards than tests: most own one
        .{ "12/16", 0 }, // and the tail owns nothing, which is not a failure
    };
    inline for (claims) |claim| {
        const run = b.addRunArtifact(fixtures);
        run.setEnvironmentVariable("BRIGADE_SHARD", claim[0]);
        run.expectExitCode(0);
        run.addCheck(.{ .expect_stdout_match = b.fmt(
            "brigade {s}: {d} passed, 0 skipped, 0 failed, 0 leaked, 0 fuzz of {d} in ",
            .{ claim[0], claim[1], claim[1] },
        ) });
        run.setName(b.fmt("partition {s} owns {d}/12", .{ claim[0], claim[1] }));
        test_step.dependOn(&run.step);
    }

    // Filter and skip are complements over the corpus's 6 even / 6 odd tags,
    // and both are applied *before* sharding -- so a narrowed run still splits.
    narrowing(b, fixtures, test_step, "even", null, 6, "filter selects the tagged half");
    narrowing(b, fixtures, test_step, null, "even", 6, "skip stands aside the tagged half");
    narrowing(b, fixtures, test_step, "fixture", "even", 6, "filter then skip compose");
    narrowing(b, fixtures, test_step, null, "fixture", 0, "an unfiltered run may legitimately select nothing");

    // A filtered run that selects nothing is a typo, and reporting it as a
    // green suite that tested zero things is the failure mode brigade exists
    // to avoid. Every shard fails on it, so the build fails whichever runs
    // first. Two ways to get there, and the message must name the right lever:
    // a filter that matched nothing, versus a skip that consumed everything
    // the filter did match.
    empty(b, fixtures, test_step, "no-such-test", null, "matched none of the 12 tests", "a filter matching nothing names the filter");
    empty(b, fixtures, test_step, "even", "even", "matched 6 of the 12 tests, and BRIGADE_SKIP='even' stood every one of them aside", "a skip that consumes the filter's whole set names the skip");

    // A malformed spec is refused rather than defaulted, for the same reason:
    // a shard that quietly owns the wrong subset is a suite that lied.
    inline for (.{ "3/3", "1", "0/0", "x/2" }) |bad| {
        const run = b.addRunArtifact(fixtures);
        run.setEnvironmentVariable("BRIGADE_SHARD", bad);
        run.expectExitCode(1);
        run.addCheck(.{ .expect_stderr_match = "BRIGADE_SHARD must be 'index/count'" });
        run.setName("a malformed BRIGADE_SHARD='" ++ bad ++ "' is refused");
        test_step.dependOn(&run.step);
    }
}

/// One unsharded run under a filter/skip pair, asserting how many of the 12
/// fixtures survive.
fn narrowing(
    b: *std.Build,
    fixtures: *std.Build.Step.Compile,
    test_step: *std.Build.Step,
    filter: ?[]const u8,
    skip: ?[]const u8,
    owned: usize,
    what: []const u8,
) void {
    const run = narrowed(b, fixtures, filter, skip);
    run.expectExitCode(0);
    run.addCheck(.{ .expect_stdout_match = b.fmt(
        "brigade 0/1: {d} passed, 0 skipped, 0 failed, 0 leaked, 0 fuzz of {d} in ",
        .{ owned, owned },
    ) });
    run.setName(what);
    test_step.dependOn(&run.step);
}

/// The same, for a pair that selects nothing *and* set a filter — which must
/// fail, and must say which lever emptied the set.
fn empty(
    b: *std.Build,
    fixtures: *std.Build.Step.Compile,
    test_step: *std.Build.Step,
    filter: []const u8,
    skip: ?[]const u8,
    because: []const u8,
    what: []const u8,
) void {
    const run = narrowed(b, fixtures, filter, skip);
    run.expectExitCode(1);
    run.addCheck(.{ .expect_stderr_match = because });
    run.setName(what);
    test_step.dependOn(&run.step);
}

fn narrowed(
    b: *std.Build,
    fixtures: *std.Build.Step.Compile,
    filter: ?[]const u8,
    skip: ?[]const u8,
) *std.Build.Step.Run {
    const run = b.addRunArtifact(fixtures);
    run.setEnvironmentVariable("BRIGADE_SHARD", "0/1");
    if (filter) |f| run.setEnvironmentVariable("BRIGADE_FILTER", f);
    if (skip) |s| run.setEnvironmentVariable("BRIGADE_SKIP", s);
    return run;
}
