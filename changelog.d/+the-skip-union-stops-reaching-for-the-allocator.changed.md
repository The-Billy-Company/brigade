`skipSpec` built the union of `-Dtest-skip` and a step's own patterns with
`std.mem.join`, which meant handling an allocation failure the build graph has
no answer for - so it did the usual thing and `@panic("OOM")`d.

`b.fmt` already owns that failure mode, and folding one pattern at a time says
the same thing in three lines with no panic token and no intermediate join.
Same output for every input, including the empty and single-pattern cases.
