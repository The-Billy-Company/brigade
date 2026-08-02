brigade ships as a package instead of a file three repositories each keep a copy
of. It was born inside a build chassis whose other half — dual C-ABI emit, a
parity-corpus generator, a macOS archive realign — is house convention nobody
outside that house wants; the runner is not. So the runner left, and the chassis
stayed.

The package is the file plus the fan-out that was never in it. `brigade.zig`
only ever decided which tests a *process* owns; the loop that turns that into
parallelism lived in each consumer's `build.zig`, three times, under a comment
admitting it was "restated here rather than shared". `build.zig` now owns it:
`init` reads `-Dtest-shards` / `-Dtest-filter` / `-Dtest-skip` and locates the
runner through `dependencyFromBuildZig`, so it resolves wherever the package was
fetched to and under whatever key the consumer named it; `runner()` hands over
the `.simple`-mode `TestRunner`; `shard()` hangs n `Run` steps off one compiled
binary; `whole()` pins a wrapper brigade cannot fan out (kcov) to a single
process; `narrowed()` answers the one question a build folding a second test
binary into `test` has to ask. Same option spellings, so nothing a consumer
types changes.

It also gets a suite, which it never had. `test/selection.zig` proves the
residue and pattern algebra through `@import("root")` — the same door a
consumer's test reaches `note` through, and the only one available, since a file
cannot be both a compilation's test runner and one of its modules.
`test/fixtures.zig` is twelve inert tests the real runner is pointed at from
outside, so every partition claim is checked against a count worked out from the
contract by hand rather than reported by the code under test. The partition
property itself — every test claimed by exactly one shard — is checked
exhaustively over shard counts 1..32 and 256 positions, because a position no
shard claims is a green suite that silently skipped it.
