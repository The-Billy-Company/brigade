---
doc_radar:
  sentinels:
    - file: brigade.zig
      contains: [BRIGADE_SHARD, BRIGADE_FILTER, BRIGADE_SKIP, BRIGADE_TIMES]
      description: "the four environment levers this README documents are the four the runner reads"
    - file: build.zig
      contains: ["test-shards", "test-filter", "test-skip", dependencyFromBuildZig]
      description: "the option triple a consumer inherits, and the self-locating dependency lookup that needs no zon key name"
    - file: brigade.zig
      contains: [".simple", disableInstrumentation]
      description: "simple-mode runner (the server protocol cannot express a parallel run), and the instrumentation opt-out the runner's own frames need"
  occurrences:
    - file: test/fixtures.zig
      pattern: '^test "fixture '
      equals: 12
      description: "build.zig's partition oracle hand-computes residue counts against a corpus of exactly twelve"
---

# brigade

**Your Zig test suite is not slow. It is serial.**

Zig's stock test runner walks `builtin.test_functions` start to finish in one
process. One core, however many the machine has. The suite this was written for
reached ~1000 tests and about eighteen minutes of wall clock at `user/real =
0.64` on a 16-core box - which is to say fifteen of those cores sat there
watching.

brigade splits the walk across processes and hands the scheduling to the build
runner you already have.

| Run | Wall |
| --- | --- |
| stock serial runner | ~1060 s |
| `zig build test` (sharded) | ~330 s - floored by one 320 s test |
| `zig build test-quick` | ~70 s |
| `-Dtest-filter="<one test>"` | ~0.1 s |

Measured on a ~1000-test suite on an otherwise idle 16-core box. Take the
ratios, not the absolutes.

## Use it

`build.zig.zon`:

```zig
.dependencies = .{
    .brigade = .{ .path = "../brigade" }, // or url + hash
},
```

`build.zig`:

```zig
const brigade = @import("brigade");

pub fn build(b: *std.Build) void {
    const bg = brigade.init(b, .{});
    const tests = b.addTest(.{ .root_module = m, .test_runner = bg.runner() });

    bg.shard(b.step("test", "Run unit tests"), tests, .{});
}
```

That is the whole integration. You now have `-Dtest-shards`, `-Dtest-filter`,
and `-Dtest-skip` on your package, and `zig build test` runs on every core.

## How it works, and why it is boring

The interesting decision is what brigade *doesn't* do.

It does not implement parallelism. A process claims the residues `i, i+n,
i+2n, ...` of `BRIGADE_SHARD=i/n`, and `Brigade.shard` hangs n independent `Run`
steps off **one** compiled binary. Zig's build runner already schedules
independent steps across cores, already renders their progress, and already
gives each one its own output pipe. So there is no thread here, no fork, no
shared state, and no interleaved stderr - a shard is just a different process.
Nothing in your suite has to become thread-safe.

Per-test semantics are byte-identical to the stock runner: fresh allocator and
`Io` instance, leak detection attributed to the test that leaked,
`error.SkipZigTest`, error-return traces, and the "a test that logs `.err`
fails" contract. Sharding is invisible to test authors.

**Residues, not blocks.** Tests are declared in module order, so cost clusters
by module - every differential in one file lands together. Striding spreads each
cluster across all shards, which is the best balance a static split can reach
without a work queue. brigade then asks for **2x** as many shards as cores, and
the build runner's own in-flight limit does the rest: a shard that drew a cheap
slice ends and the next starts, instead of a core idling beside a grinding
neighbor.

**One caveat, stated plainly.** A shard is a process, so two tests that collide
on a fixed external name - the same `/tmp` fixture path, the same listening
socket - can now run at the same time. Key those per test and per pid.
`-Dtest-shards=1` restores a single-process run for a bisect or a debugger.

## Levers

| Lever | Effect |
| --- | --- |
| `-Dtest-shards=N` | processes to split across. Default 2x CPU count, capped at 64. `1` restores a single-process run. |
| `-Dtest-filter=<substr,...>` | run only tests whose name contains one of these. **A name copied out of a FAIL line is already a valid filter.** |
| `-Dtest-skip=<substr,...>` | the inverse. |
| `BRIGADE_TIMES=1` | emit `<ms>\t<name>` per test - how you find a long pole in the first place. |

Each spelling caches separately, because a shard's environment is part of its
cache key. An unchanged tree replays a proven-green shard instead of re-running
it, and only a success is ever recorded.

### The quick tier

Sharding cannot split one test, so past some point the slowest *single* test is
the floor. Name the long poles and get a tier that stands them aside:

```zig
bg.shard(b.step("test", "Run unit tests"), tests, .{});
bg.shard(b.step("test-quick", "the suite minus its long poles"), tests, .{ .skip = &deep });
```

`test` stays the complete suite and remains what a push is judged by;
`test-quick` is a deliberately weaker proof for the edit loop. A `deep` entry
that stops matching - renamed, deleted - is reported by name, and can only ever
make the quick tier slower, never less safe.

## Which stream a test writes to is a correctness question

This one costs people a week if they discover it themselves, so it is worth
saying up front.

The build runner renders any step with **non-empty stderr** through its failure
printer - step name, the text, a `failed command: <argv>` caption - whether or
not the step failed. (`build_runner.zig`: *"No matter the result, we want to
display error/warning messages"*; `result_failed_command` is populated for a
success too.) So stderr is not "the diagnostic stream" here. It is the stream
that makes a green shard look dead. Seven narrating tests in one suite made
every green run print seven blocks indistinguishable from seven crashed
processes, which is how you teach people to stop reading test output.

So: `note` for what a **passing** test proved, on stdout, which the build step
captures and drops. `std.debug.print` for what a reader must act on.

```zig
const brigade = @import("root"); // the runner is your test binary's root module

test "differential over the corpus" {
    // ...
    brigade.note("{d} comparisons, 0 mismatches\n", .{pairs});
}
```

The trade, stated rather than discovered: because the build step drops stdout, a
*failing* shard's narration is dropped with it. That is why a red shard closes
by printing the one `BRIGADE_SHARD=... BRIGADE_FILTER=...` command that replays
it in full.

## What it refuses to do

- **Silently own the wrong subset.** A malformed `BRIGADE_SHARD` is fatal, not
  defaulted. A shard that quietly owns nothing is a green suite that tested
  nothing.
- **Report an empty filtered run as green.** A filter that selects zero tests
  fails every shard, and says which lever emptied the set - the filter matching
  nothing, or a skip that consumed everything the filter did match.
- **Allocate to answer "which shard am I".** Every environment key is a
  compile-time literal; the Windows arm transcodes WTF-16 out of the PEB into a
  fixed buffer.
- **Speak `std.zig.Server`.** That protocol hands out one test index at a time
  and awaits its result, so it cannot express a parallel run. brigade is a
  `.simple`-mode runner judged by its exit code. Coverage-guided fuzzing needs
  the protocol, so `std.testing.fuzz` here degrades to replaying the declared
  corpus plus the empty input - keep `zig build fuzz` on the stock runner.

## Prior art

- **Zig's own default runner** (`lib/compiler/test_runner.zig`, MIT). brigade
  reimplements its per-test semantics deliberately and exactly; the only
  difference is which tests a process claims. Upstream has discussed parallel
  testing for years ([ziglang/zig#1636](https://github.com/ziglang/zig/issues/1636))
  without landing it, largely because the server protocol is index-at-a-time.
- **Go's `go test -parallel`** and **Rust's libtest thread pool** both
  parallelize *within* one process, which requires every test to be
  thread-safe. brigade takes the process route precisely to avoid imposing that
  on suites that were never written for it - the same trade `cargo-nextest`
  makes, and for the same reason.
- **[cargo-nextest](https://nexte.st/)** (Rust, process-per-test). The closest
  relative in spirit. brigade runs a process per *shard* rather than per test,
  because a Zig test binary's startup is cheap but not free at ~1000 tests, and
  because the build runner - not brigade - should own the scheduling.

## Testing brigade

```bash
zig build test          # the suite, run by brigade itself
zig build test -Dtest-shards=1
zig build check         # compile without running (--watch / ZLS)
```

Two layers, because the two halves fail differently. `test/selection.zig`
proves the residue and pattern algebra in-process - including, exhaustively
over shard counts 1..32 and 256 positions, that **every test is claimed by
exactly one shard**. `test/fixtures.zig` is a corpus of twelve inert tests that
the real runner is pointed at from outside, so every partition claim is checked
against a count worked out from the residue contract by hand rather than
reported by the code under test.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
