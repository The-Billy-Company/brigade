---
doc_radar:
  sentinels:
    - file: .markdownlint-cli2.jsonc
      contains: ['"filter": ["changelog.d/*.md", "!changelog.d/README.md"]', '"config": { "MD041": false }', '"combine": "merge"']
    - file: .github/workflows/release.yml
      contains: ['command: notes', '--notes-file /tmp/release-notes.md']
    - file: release-please-config.json
      contains: ['"always-update": true', '"include-component-in-tag": false']
      absent: ['"package-name"']
    - file: brigade.zig
      contains: ['.init(std.heap.page_allocator', 'allocation_check != 0', 'std.enums.EnumIndexer(std.log.Level)']
    - file: build.zig.zon
      contains: ['.minimum_zig_version = "0.16.0"', '.dependencies = .{}']
    - file: .github/workflows/ci.yml
      contains: ['ZIG_VERSION: 0.16.0', 'zoning==1.4.0', 'zizmor==1.30.1', 'version: "latest-known"', "group: ci-${{ github.ref == 'refs/heads/main' && github.sha || github.ref }}"]
    - file: .github/workflows/release-please.yml
      contains: ['towncrier==26.9.0', 'export SOURCE_DATE_EPOCH']
---

# `changelog.d/` — towncrier news fragments

Per-change fragments for `brigade`. They fold into
[`../CHANGELOG.md`](../CHANGELOG.md) on release build — not something you
hand-edit into the changelog mid-PR.

```bash
towncrier create +<slug>.<type>.md
# write the fragment body, then on release:
towncrier build --version x.y.z
```

Fragment shape: `+<slug>.<type>.md`. Write one in the **same PR** as any
user-visible / API / behavior / perf / security change. Skip only for
comment-only, format-only, or pure-internal refactors with zero observable
delta — when unsure, write the fragment.

Fragments are Markdown and keep their own layout: `wrap = false` in
[`../towncrier.toml`](../towncrier.toml), so multiple paragraphs, fenced code,
and lists survive the fold. Match the surrounding document — dash bullets,
fenced blocks — since the fold lands them in one file with everything else.
