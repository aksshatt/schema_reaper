# Changelog

## [1.0.2] - 2026-09-04

### Changed
- Lowered `required_ruby_version` to `>= 2.7.0` (was `>= 3.1.0`).
  - Rewrote all 40 endless method definitions (`def x = ...`, a Ruby 3.0
    feature) as classic `def ... end`.
  - Added explicit `require "set"` where `Set` / `to_set` are used (autoloaded
    only on Ruby 3.2+).
  - `rubocop` `TargetRubyVersion` set to 2.7; CI matrix now 2.7–3.3.
  - Every `lib/`, `spec/` and `exe/` file verified to parse under Ruby 2.7.0;
    dependency-free modules exercised on a real 2.7 runtime. Runtime deps
    (`prism` >= 2.7, `thor` >= 2.6, `pg`) all support 2.7.
- No behaviour change; 29 specs unchanged.

## [1.0.1] - 2026-09-04

Superseded by 1.0.2 before release. Lowered the floor to `>= 3.0.0` only.

## [1.0.0] - 2026-09-04

First stable release.

### Analyzers
- `dead_column` — schema column never referenced in code; fuses in runtime
  signal when present to break the 0.6 static-only confidence cap.
- `dead_table` — table with no model/query reference and (when known) zero rows.
- `unused_index` — non-unique index with `idx_scan = 0` in `pg_stat_user_indexes`.
- `duplicate_index` — index that is a leading prefix of a wider index.
- `missing_fk_index` — foreign-key / `*_id` column with no covering index.
- `always_null_column` — column with `null_frac = 1.0` in `pg_stats`.
- `single_value_column` — column with one distinct value on a large table.

### Signal
- Postgres introspection now also reads row counts (`pg_class.reltuples`),
  per-column `pg_stats` (`null_frac`, `n_distinct`) and index scan counts.
- Optional runtime tracker: samples ActiveRecord attribute reads into a JSONL
  log; `Runtime::Report` aggregates it and analyzers fuse it in.
- Gem-awareness maps auto-whitelist columns owned by devise, paper_trail,
  audited, friendly_id, activestorage, actiontext, pg_search, ahoy_matey and
  the paranoia family, scoped to tables that actually carry the anchor column.

### Output & workflow
- Reporters: `table`, `json`, `markdown` (PR-comment ready), `sarif` 2.1.0
  (GitHub code scanning).
- Reclaimable-bytes estimate per finding and per run, from row counts.
- `schema_reaper trend` + append-only history log for cleanup burndown.
- `scan --ci` gates only findings absent from `.schema_reaper/baseline.json`;
  `scan --record`, `scan --min-confidence`.
- Whole-dead-table findings suppress their own column/index noise.
- Rails railtie: `rake schema_reaper:scan|baseline|trend`, opt-in runtime
  tracker via `SCHEMA_REAPER_TRACK=1`.
- Custom analyzers loadable through the `require:` config key.

### Not in 1.0 (planned)
- MySQL adapter.
- Mountable dashboard engine.
- Orphan-row and schema-drift analyzers.

## [0.1.0]
- Initial scaffold: `dead_column` static analyzer, table/JSON reporters,
  baseline, staged migration generator.
