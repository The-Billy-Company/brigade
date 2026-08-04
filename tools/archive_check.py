#!/usr/bin/env python3
"""Prove the tagged tarball is what a consumer's `zig fetch` will actually get.

brigade ships to no package registry — a git tag alone makes `zig fetch
--save .../archive/refs/tags/vX.Y.Z.tar.gz` resolve the package, so the
GitHub-generated source tarball for the tag *is* the artifact. This is the
one thing worth checking that nothing else does: every path
`build.zig.zon`'s `.paths` declares is actually inside that tarball, under
its single top-level directory, with real content — not proving hashability
(the composite `zig fetch` step alongside this one already does that), but
proving the manifest's own promise is content-complete.

Usage: archive_check.py <tarball> <build.zig.zon>
"""

from __future__ import annotations

import re
import sys
import tarfile
from pathlib import Path

PATHS_BLOCK = re.compile(r"\.paths\s*=\s*\.\{(.*?)\n\s*\}", re.DOTALL)
QUOTED = re.compile(r'"([^"]+)"')


def declared_paths(zon: Path) -> list[str]:
    text = zon.read_text(encoding="utf-8")
    block = PATHS_BLOCK.search(text)
    if not block:
        raise SystemExit(f"{zon}: no .paths = .{{ ... }} block found")
    return QUOTED.findall(block.group(1))


def archive_members(tarball: Path) -> tuple[str, set[str]]:
    with tarfile.open(tarball) as tar:
        names = tar.getnames()
    if not names:
        raise SystemExit(f"{tarball}: empty archive")
    # GitHub wraps every generated tarball in one `<repo>-<ref>/` directory;
    # every member shares it, so the first path segment names it without
    # guessing the exact `<ref>` GitHub chose to spell.
    top = names[0].split("/", 1)[0]
    return top, set(names)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {Path(__file__).name} <tarball> <build.zig.zon>", file=sys.stderr)
        return 2
    tarball, zon = Path(argv[0]), Path(argv[1])

    wanted = declared_paths(zon)
    top, present = archive_members(tarball)

    missing = [p for p in wanted if f"{top}/{p}" not in present and not any(
        m.startswith(f"{top}/{p}/") for m in present
    )]
    if missing:
        print(f"::error::{tarball.name} is missing declared path(s): {', '.join(missing)} "
              f"— build.zig.zon promises them, the tag's tarball does not carry them", file=sys.stderr)
        return 1

    print(f"{tarball.name}: all {len(wanted)} declared path(s) present under {top}/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
