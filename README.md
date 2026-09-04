# schema_reaper

Find dead columns, dead tables, unused indexes and other schema dead-weight in
Rails / ActiveRecord apps — then remove them safely.

`schema_reaper` reads your **live PostgreSQL schema and planner statistics** and
cross-references them against a **static scan of your codebase** (Ruby via the
Prism AST, plus views and SQL string literals). Optionally it also fuses in a
**runtime signal** — a sampled log of which columns are actually read in
production. Every finding is scored by confidence and severity, carries an
estimate of the disk it reclaims, and comes with a concrete fix.

## Install

```ruby
# Gemfile
gem "schema_reaper", group: :development
```

```
bundle install
```

Requires Ruby >= 3.1 and PostgreSQL. The database connection resolves from
`database_url` in `.schema_reaper.yml`, else `ENV["DATABASE_URL"]`.

## Usage

```
bundle exec schema_reaper scan                    # human-readable report
bundle exec schema_reaper scan --format markdown  # PR-comment table
bundle exec schema_reaper scan --format sarif     # GitHub code scanning
bundle exec schema_reaper scan --format json
bundle exec schema_reaper scan --ci               # exit 1 on new findings
bundle exec schema_reaper scan --min-confidence 0.8
bundle exec schema_reaper baseline                # accept current findings
bundle exec schema_reaper trend                   # snapshot + progress delta
bundle exec schema_reaper generate-migration users legacy_api_token
```

In a Rails app the railtie also gives you
`rake schema_reaper:scan|baseline|trend` (with `FORMAT=`).

## Analyzers

| type | what it flags | main signal |
|---|---|---|
| `dead_column` | column no code path references | static scan (+ runtime) |
| `dead_table` | table with no model/query reference | static scan + row count |
| `unused_index` | non-unique index, `idx_scan = 0` | `pg_stat_user_indexes` |
| `duplicate_index` | index that is a prefix of a wider one | schema shape |
| `missing_fk_index` | `*_id` / FK column with no index | schema shape |
| `always_null_column` | `null_frac = 1.0` — no data at all | `pg_stats` |
| `single_value_column` | one distinct value on a large table | `pg_stats` |

Columns owned by common gems (devise, paper_trail, activestorage, actiontext,
friendly_id, audited, pg_search, ahoy_matey, paranoia family) are whitelisted
automatically when the gem is in your bundle.

## Runtime signal (optional, raises confidence)

Static analysis alone can't see metaprogrammed access, so `dead_column`
confidence is capped at **0.6** without runtime data. To lift the cap:

```ruby
# config/initializers or manually
SchemaReaper::Runtime::Tracker.install!(
  store: SchemaReaper::Runtime::Store.new(path: ".schema_reaper/runtime.jsonl"),
  sample_rate: 0.05
)
```

or, in Rails, boot with `SCHEMA_REAPER_TRACK=1`. Let it run in staging or
production for a couple of weeks. A column unseen in **both** code and
>= 14 observed days of runtime data reaches ~0.9 confidence.

## Safety model

`schema_reaper` never drops anything itself. `generate-migration` emits a pair:

1. **Ignore** — you add `self.ignored_columns += %w[col]` to the model and
   deploy. Nothing is dropped.
2. **Drop** — run only after step 1 has soaked in production and nothing broke.

`always_null_column` / `single_value_column` fixes ask you to confirm with a
`SELECT` first.

## CI

```yaml
# .github/workflows/schema_reaper.yml
- run: bundle exec schema_reaper scan --ci --format sarif > reaper.sarif
- uses: github/codeql-action/upload-sarif@v3
  with: { sarif_file: reaper.sarif }
```

Commit `.schema_reaper/baseline.json` so the job fails only when a change adds
*new* dead weight.

## Custom analyzers

```ruby
# lib/schema_reaper/analyzers/my_check.rb
class MyCheck < SchemaReaper::Analyzers::Base
  SchemaReaper::Analyzers::Registry.register(self)

  def call
    schema.tables.filter_map { |t| ... finding(type: :my_check, table: t.name, ...) }
  end
end
```

```yaml
# .schema_reaper.yml
require:
  - lib/schema_reaper/analyzers/my_check.rb
```

## Roadmap

- Runtime verdict fusion for index and table findings
- Orphan-row and `schema.rb`↔DB drift analyzers
- Disk/$ reclaim from real `pg_total_relation_size`
- Mountable dashboard engine, trend charts
- MySQL adapter

## Development

```
bin/setup
bundle exec rake        # rspec + rubocop
```

## License

MIT.
