The install section said `url + hash` and left the reader to derive both, because
until v0.1.0 there was no tag to derive them from - the only honest spelling was
a raw commit tarball, which is not something a README should teach.

It now leads with `zig fetch --save` against the tagged archive, which writes
both fields and re-derives the hash itself, and keeps the sibling-checkout path
dependency as the second form rather than the first. That ordering matches who
is reading: someone adopting the package has no checkout beside theirs.
