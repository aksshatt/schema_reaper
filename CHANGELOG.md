# Changelog

## [1.0.13] - 2026-09-18

### Fixed
- **Expression key columns were silently dropped from an index's column
  list.** `indexes_for` joined `pg_index.indkey` entries against
  `pg_attribute` by `attnum`; an expression column's `indkey` entry is
  `0`, which matches no real column, so the join dropped it instead of
  erroring. An index on `((data ->> 'type')), ((data ->> 'id')), user_id,
  created_at` came back as just `user_id,created_at`, which then made a
  plain index on `:user_id` look like a genuine leading-edge duplicate of
  a key it was not actually a prefix of -- `duplicate_index` recommended
  dropping an index that ordinary `WHERE user_id = ?` lookups depended
  on. Rewritten to use `pg_get_indexdef(indexrelid, column_no, pretty)`,
  which is keyed by column position rather than table attnum and renders
  a plain column and an expression the same way. Also switched the
  internal column separator from `,` to a control byte, since an
  expression can legitimately contain a comma (`COALESCE(a, b)`) that a
  comma-delimited split would have cut in half. (#9, mitkush)
- **A table a gem creates and owns outright could be reported as dead.**
  `dead_table` never consulted `GemAwareness`, so a table only ever
  referenced through a gem's own internal classes -- never named in app
  code -- looked exactly like real dead weight. Confirmed on a real app:
  all of that app's `dead_table` findings were gem-owned tables
  (`active_admin_comments`, `devise_api_tokens`, `friendly_id_slugs`),
  and `drop_table :devise_api_tokens` would have deleted its mobile
  session storage. `GemAwareness.owned_tables` now feeds `dead_table` the
  same way it already fed the `dead_column` exemption. Also added
  `activeadmin` and `devise-api` to the gem map, verified against each
  gem's own migration template. (#10, mitkush)

## [1.0.12] - 2026-09-15

### Fixed
- **`--format markdown` claimed `0 B reclaimable` when the row count was
  unknown.** `Table` learned in 1.0.11 that `reclaimable_bytes` is `nil`
  both when the true value is zero and when the row count has never been
  measured, and that a report should say which. `Markdown` summed the raw
  bytes directly and always printed a total, so on an unanalysed database
  it stated there was nothing to reclaim — the exact claim the 1.0.11 fix
  was written to stop, just in the one format meant for an unattended PR
  comment or CI job summary. The per-row `Reclaims` column had the same
  bug: an unmeasured finding showed `0.0 B`, indistinguishable from one
  that genuinely frees nothing. The summary/unmeasured logic now lives in
  one shared `Reporters::Reclaim` module used by both reporters, so the
  two formats cannot answer the same question differently again. (#7,
  mitkush)

## [1.0.11] - 2026-09-15

Everything below landed after 1.0.10 was cut, so 1.0.10 on RubyGems contains
none of it.

### Fixed
- **Composite index columns were read in table order, not index-key order.**
  `indexes_for` aggregated with `ORDER BY a.attnum` — a column's position in
  the *table* — so `(company_id, email)` came back as `email,company_id`.
  Since `Index#covers?` is a prefix test, this broke `duplicate_index` in both
  directions: it recommended `remove_index` on indexes that are not redundant
  (dropping one would degrade queries on its leading column), and missed
  genuinely redundant ones. `missing_fk_index` read the same corrupted order
  through `indexed?`. Now joins `unnest(indkey) WITH ORDINALITY`. (#1, mitkush)
- **`primary_key_for` returned one arbitrary column of a composite key.** It
  matched `attnum = ANY(indkey)` with no `ORDER BY` and took `.first`, so the
  other key columns looked like ordinary columns to the analyzers and could be
  reported as `dead_column` or `single_value_column` — suggesting you drop part
  of a primary key. Now returns every key column in order; `Table#primary_key?`
  accepts a name or a list. (#1, mitkush)
- **Polymorphic associations were reported as unindexed foreign keys.** A
  `*_id` paired with a `*_type` is only ever queried with the type, so the
  index that matters is the composite `(type, id)` — but `indexed?` only asked
  whether the column led *some* index. Rails apps were told to add an index the
  planner would never use. (#1, mitkush)
- **`dead_table` missed models behind `-ies` tables and route helpers.**
  `referenced?` singularised with `sub(/s\z/, "")`, turning `crm_activities`
  into `crm_activitie`, so `CrmActivity` never matched. Because
  `drop_findings_on_dead_tables` discards every column- and index-level finding
  for a table called dead, one bad `dead_table` silently suppressed everything
  else about that table. Inflection now handles `-ies`/`-sses`/`-xes`, and a
  table name is also matched inside longer identifiers such as
  `admin_crm_activities_path`. (#1, mitkush)
- **Ruby 2.7 was broken despite being the declared floor.** `Config.load`
  called `YAML.safe_load_file`, which arrived in Psych 3.3 (Ruby 3.0), so every
  command crashed for any 2.7 user with a `.schema_reaper.yml`.
  `Console#title` appended to an interpolated string, which is frozen on
  Ruby <= 2.7. (#2, mitkush)
- **`config/database.yml` credentials were not URL-escaped.** A password
  containing `@` made libpq read the rest as the host, reporting
  `could not translate host name "ss@localhost"` — a hostname the user never
  configured. Also, when ERB failed to render (commonly
  `Rails.application.credentials` outside a booted Rails), the resolver fell
  back to parsing the file *un-rendered* and built a connection URL out of
  template text; it now resolves nothing so the real error surfaces. (#1,
  mitkush)
- **An unknown reclaim estimate was printed as `0 B`.** A byte estimate needs a
  row count, and `reltuples = -1` means unknown; `Base#finding` turned that into
  zero, so reports opened with `~0.0 B reclaimable` — "nothing to gain" rather
  than "cannot say". (#4, mitkush)

### Changed
- **`unused_index` is skipped when the database has no query history.**
  `idx_scan = 0` means either "never used" or "this database has answered no
  queries". On a freshly loaded schema the analyzer reported every non-unique
  index — 197 of 266 findings on one app. It now compares cluster-wide
  `idx_scan` against the index count and explains the skip on stderr. (#2,
  mitkush)
- **`missing_fk_index` confidence is tiered by evidence.** A declared FK
  constraint scores 0.9; a `*_id` name with a table it plausibly references
  scores 0.7; a `*_id` name with nothing to reference scores 0.5 and drops to
  `:low`. Previously `voter_id` and `upi_id` were reported as confidently as a
  real constraint, which made `--min-confidence` useless for this analyzer.
  Nothing is dropped. (#3, mitkush)
- **The report says what it contains.** The header now carries the finding
  count, how many tables are affected, and the type breakdown — previously only
  a tally in the footer, 245 lines below on a large report. (#4, mitkush)
- **Findings that differ only in the names they mention are rolled up.** 37
  missing foreign-key indexes spent 111 lines repeating one sentence. They now
  collapse into a single entry that keeps the confidence bar, states the fix as
  a template, and lists every target. Nothing is summarised away, and findings
  whose evidence genuinely differs — every `duplicate_index` names a different
  index pair — stay itemised. 246 lines to 124 on one app. (#5, mitkush)

## [1.0.10] - 2026-09-09

Supersedes 1.0.9, which was published to RubyGems from an incomplete cut and
is missing the fixes below. Use 1.0.10.

### Added
- Automatic database connection in a Rails app. If `database_url:` is not set in
  `.schema_reaper.yml` and `DATABASE_URL` is not in the environment,
  schema_reaper now reads `config/database.yml` — rendering ERB, resolving YAML
  aliases, honouring `SCHEMA_REAPER_ENV` / `RAILS_ENV` (default `development`),
  and handling Rails 6+ multi-database sections. `bundle exec schema_reaper
  scan` works with no setup. PostgreSQL adapters only.
- Connection and missing-config errors now print a one-line `✗` message
  instead of a Ruby backtrace.

### Fixed
- `pg_class.reltuples` is `-1` on PostgreSQL 14+ for a table that has never
  been analysed. It was being treated as a real row count: `dead_table`
  printed "table holds ~-1 row(s)", scored it at the 0.4 "non-empty" level,
  and the reclaimable-bytes estimate went negative. A negative `reltuples` is
  now mapped to "unknown" — the finding drops to 0.5 confidence, the evidence
  says the count is unknown and suggests running `ANALYZE`, and the byte
  estimate stays at 0. Found by running against a real production schema.

### Changed
- Redesigned the terminal report (`scan` / `scan --format table`):
  - one summary line (finding count + total reclaimable),
  - findings grouped under their table, sorted by confidence,
  - a five-cell confidence bar with the percentage, padded severity and
    analyzer name, the target column/index, and the reclaimable size,
  - evidence on one dim `·`-joined line, the fix on a green `→` line,
  - a footer with a severity tally and a per-analyzer breakdown.
- Colour is automatic on an interactive terminal and suppressed when output
  is piped or `NO_COLOR` is set. New `scan --color` / `--no-color` to force it.
- JSON, SARIF and Markdown reporters are unchanged.
- `trend` now prints a readable progress block — finding count and reclaimable
  total with signed deltas since the first and previous run, a list of findings
  newly introduced and resolved, and the snapshot dates — instead of a raw
  `pp` hash dump.
- `baseline` and `generate-migration` print a short titled block with a `✓`
  line and next steps; `generate-migration` spells out the two-step deploy.
- `scan --ci` reports new findings as a `✗` block on stderr with the finding
  ids indented under it.
- The "unused_index skipped / no query history" message is now a single
  formatted `!` notice on stderr.

## [1.0.8] - 2026-09-04

### Fixed
- `missing_fk_index` no longer advises `add_index` on a foreign-key column
  that is NULL in every row of a non-empty table. Indexing an empty column is
  pointless, and `always_null_column` already flags it for removal; the
  higher-confidence `missing_fk_index` finding was previously winning the
  per-column collapse and producing "add an index to this dead column".
  Found by a clean-room run of 1.0.7 against a live database.

## [1.0.7] - 2026-09-04

Correctness fixes to introspection and analyzers, all contributed by @mitkush
and verified against a live PostgreSQL database.

### Fixed
- **Index-key order** (#1). Index columns are now read in real key order via
  `unnest(indkey) WITH ORDINALITY` instead of `attnum` order, so
  `duplicate_index`'s prefix comparison is correct for composite indexes.
- **`unused_index` false positives on quiet databases** (#2). If the whole
  cluster has fewer recorded index scans than it has indexes, there is no
  query history to judge by -- the analyzer now skips with an explanation
  instead of flagging every index as unused.
- **Polymorphic associations in `missing_fk_index`** (#3). A `*_id` column
  paired with a `*_type` column is matched against the composite
  `(type, id)` index Rails actually uses; a bare `*_id` index is no longer
  demanded, and when the pair is unindexed the suggested fix is the composite
  `add_index :t, %i[thing_type thing_id]`.
- **`dead_table` plurals and route helpers** (#5). Tables whose model name
  needs `-y -> -ies` (`categories` -> `Category`) and names referenced only
  through route helpers are recognised as used.
- **Composite primary keys** (#6). Introspection returns every primary-key
  column in key order; `Table#primary_key?` / `#primary_key_columns` let
  analyzers treat each part of a composite key as a key column.

### Changed
- `DatabaseSchema` carries `index_scan_total`; `Table#primary_key` may now be
  an array. Test helpers updated accordingly.

## [1.0.6] - 2026-09-04

### Changed
- Added `mitkush` (mitanshukushwah@gmail.com) as a gemspec author.

## [1.0.5] - 2026-09-04

Fixes found by running the gem against a live PostgreSQL database.

### Fixed
- **Duplicate findings for one object.** When several analyzers flagged the
  same physical column (e.g. `dead_column` + `always_null_column`) or index
  (`unused_index` + `duplicate_index`), each was reported separately *and* its
  reclaimable bytes were counted more than once, inflating the run total.
  Findings are now collapsed to the highest-confidence one per target; the
  others are noted as `also flagged by: ...` in its evidence.
- **`generate-migration` output.** The generated STEP 1 migration contained a
  fragile multi-line string (heredoc line-continuation) that rendered with a
  stray gap. It is now a single clean string. Both files are verified valid
  Ruby.
- **Migration schema version.** Generated migrations now inherit the host
  app's Rails minor version (`ActiveRecord::Migration[X.Y]`) when ActiveRecord
  is loaded, instead of a hard-coded `7.1`.

### Added
- Specs covering target collapsing and migration generation, exercised end to
  end through `Runner` with an injected schema.

## [1.0.4] - 2026-09-04

### Changed
- Rewrote `description` as a single tight paragraph. RubyGems collapses
  description whitespace, so the previous multi-line bulleted text rendered as
  an unreadable blob on the gem page. Full analyzer list and usage stay in the
  README. Link metadata from 1.0.3 unchanged.

## [1.0.3] - 2026-09-04

### Changed
- Richer gem metadata for the RubyGems page: expanded `description` (analyzer
  list, safety model, gem-awareness, reporters), and added `bug_tracker_uri`,
  `documentation_uri`, `wiki_uri` and `funding_uri` (GitHub Sponsors) link
  metadata. No code change.

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
