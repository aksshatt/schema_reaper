# Changelog

## [0.1.0] - unreleased

### Added
- `schema_reaper scan` — Postgres schema introspection + Prism-based static
  code scan, `dead_column` analyzer, table and JSON reporters.
- `schema_reaper baseline` and `scan --ci` for gating only *new* findings.
- `schema_reaper generate-migration TABLE COLUMN` — staged, reversible
  ignore + drop migration pair.
- `.schema_reaper.yml` configuration with ignore lists, scan paths and
  always-keep columns.
