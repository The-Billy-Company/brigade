We keep the advertised Zig 0.16 floor, and the runner also compiles with 0.17.
It uses SafeAllocator on the new compiler, with the stock test runner's checks and
per-test leak accounting. Real process fixtures prove a leak fails its run,
leaves the next test clean, and keeps errors and skips in their own counts.

CI and release stay on the compiler that has cleared quarantine. We updated
checkout, uv setup,
actionlint, zizmor, zoning and towncrier; the new uv selector uses the action's
known checksums, and every direct Python tool resolution keeps a two-day floor.
Main gives each commit its own CI group, so a later push cannot cancel its
release evidence.

Changelog folds use the release PR's commit timestamp. The same source gets the
same date when the fold is retried, through towncrier's new SOURCE_DATE_EPOCH
support. The runner's public API and its summary format stay the same.

We also join the folded changelog to the GitHub release body through the shared
release action's new notes command. The bot's standalone component config now
agrees with the component-free tag, and every main push refreshes the open PR
so a hidden docs or CI commit cannot leave its fragments behind.
