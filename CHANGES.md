# Changes

## 1.0.0 — 2026-09-23 (DIVE-4891)

- Council moves out of the 5dive core CLI into this repository (DIVE-4869 phase 2).
  The engine, CLI and bash body are core's `src/council/` at fcd81d73, carried
  verbatim apart from seven marked `PLUGIN DIVERGENCE` sites, each replacing an
  in-process call into core with a core CLI verb.
- Existing `/var/lib/5dive/council/` state is read and written in place; a lineage
  sealed by the built-in council verifies here and the reverse.
- 29 of core's 30 `tests/council_*` harnesses move here with core's pass counts
  unchanged; the 30th (`council_unit.sh`) was an aggregator and is replaced by
  `tests/run_all.sh`.
