# Changelog

All notable changes to `brigade` (the shard-aware Zig test runner) are
documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versions track
`build.zig.zon`.

<!-- towncrier release notes start -->

## [0.1.0] - 2026-08-03

### Added

- brigade ships as a package instead of a file three repositories each keep a copy
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

### Changed

- The README was restyled to the house shape: a contents list, one idea per
  paragraph, and headings that label a section rather than argue with it. Both
  tables - the measurements and the levers - became lists, because a two-column
  table was always a bulleted list wearing a grid.

  Three sections are new rather than restyled. Who this is for and who should stay
  on the stock runner now sit at the top, where a reader in the wrong repository
  can leave in a paragraph; and a support section says where a bug goes, where a
  vulnerability goes, and which tracker owns a failure in a downstream suite.

  No claim moved. Every number, path, and flag the old text asserted is still
  there. The doc-radar frontmatter came off with it - that gate lives in the
  monorepo brigade was extracted from, and it never ran here.
- `skipSpec` built the union of `-Dtest-skip` and a step's own patterns with
  `std.mem.join`, which meant handling an allocation failure the build graph has
  no answer for - so it did the usual thing and `@panic("OOM")`d.

  `b.fmt` already owns that failure mode, and folding one pattern at a time says
  the same thing in three lines with no panic token and no intermediate join.
  Same output for every input, including the empty and single-pattern cases.

### Fixed

- A filtered run that selects nothing now says which lever emptied the set.

  brigade fails such a run on purpose — a filter that matches no test is a typo,
  and reporting it as a green suite that tested exactly zero things is the failure
  mode the runner exists to prevent. But it counted survivors *after* applying the
  skip and then blamed the filter for the number, so `BRIGADE_FILTER='even'
  BRIGADE_SKIP='even'` reported `matched none of the 12 tests` when the filter had
  in fact matched six and the skip had stood all six aside. The reader goes and
  stares at the wrong variable.

  Filter matches are counted separately from post-skip survivors now, and the two
  emptinesses have their own message: `matched none of the N tests` when the
  filter found nothing, and `matched M of the N tests, and BRIGADE_SKIP='…' stood
  every one of them aside` when it found something the skip then consumed. Both
  still exit 1 from every shard, so the build fails whichever one the runner
  reaches first.

  Found by writing the adverse case rather than by hitting it: the behavior was
  inherited unchanged by all three copies of the runner that existed before this
  package did.
