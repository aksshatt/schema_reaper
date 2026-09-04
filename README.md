# schema_reaper

Find dead columns, unused indexes and schema dead-weight in Rails / ActiveRecord
apps — then remove them safely.

`schema_reaper` reads your **live database schema** and cross-references it
against a **static scan of your codebase** (Ruby via Prism AST, plus views and
SQL string literals). Anything in the schema that nothing in the code references
is reported as a finding, scored by confidence and severity, with an estimate of
the bytes per row it reclaims and a **two-step reversible migration** to drop it.

> v0.1 is static-signal only, so `dead_column` confidence is capped at 0.6.
> Runtime instrumentation and `pg_stat_*` fusion (raising confidence toward 1.0)
> are on the roadmap.

## Install

```ruby
# Gemfile
gem "schema_reaper", group: :development
```

```
bundle install
```

## Usage

```
bundle exec schema_reaper scan                 # human-readable report
bundle exec schema_reaper scan --format json   # machine-readable
bundle exec schema_reaper scan --ci            # exit 1 on findings not in baseline
bundle exec schema_reaper baseline             # accept current findings as the baseline
bundle exec schema_reaper generate-migration users legacy_ssn_hash
```

Database connection resolves from `database_url` in `.schema_reaper.yml`, else
`ENV["DATABASE_URL"]`. Postgres only for now.

## Configuration

Copy `.schema_reaper.yml.example` to `.schema_reaper.yml`. All keys optional; see
the example file for defaults.

## Safety model

`schema_reaper` never drops anything itself. `generate-migration` emits a pair:

1. **Ignore** — a reminder migration; you add `self.ignored_columns += %w[col]`
   to the model and deploy. Nothing is dropped.
2. **Drop** — run only after step 1 has soaked in production and you have
   confirmed nothing broke.

## CI

```yaml
# .github/workflows/schema_reaper.yml
- run: bundle exec schema_reaper scan --ci
```

Commit `.schema_reaper/baseline.json` so the job only fails when a change adds
*new* dead weight.

## Roadmap

- Runtime attribute-access instrumentation + verdict fusion
- Unused / duplicate / missing index analyzers (`pg_stat_user_indexes`)
- Always-NULL / single-value / duplicate column analyzers
- Disk + `$` reclaim estimation from row counts
- History snapshots and trend reporting
- Mountable dashboard engine, SARIF reporter
- MySQL adapter

## Development

```
bin/setup
bundle exec rspec
bundle exec rubocop
```

## License

MIT.
