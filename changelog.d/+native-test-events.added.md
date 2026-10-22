---
doc_radar:
  sentinels:
    - file: brigade.zig
      contains: ['"BRIGADE_EVENTS"', 'error.MissingTestSource', 'runner_io.randomSecure']
---

We can retain native collection, deselection, outcomes and measured runtimes with `BRIGADE_EVENTS=<directory>`. The compiler supplies each original source location, including anonymous tests; every shard writes its own exclusive stream. Ordinary runs keep their existing output and test behavior.
