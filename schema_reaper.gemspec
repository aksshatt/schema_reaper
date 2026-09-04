# frozen_string_literal: true

require_relative "lib/schema_reaper/version"

Gem::Specification.new do |spec|
  spec.name = "schema_reaper"
  spec.version = SchemaReaper::VERSION
  spec.authors = ["aksshatt"]
  spec.email = ["akshatpegwar5@gmail.com"]

  spec.summary = "Find dead columns, dead tables, unused indexes and other schema dead-weight " \
                 "in Rails/ActiveRecord apps -- then remove it safely."
  spec.description = <<~DESC
    schema_reaper reads your live PostgreSQL schema and planner statistics and
    cross-references them against a Prism-AST static scan of your codebase
    (models, views, SQL string literals). With an optional runtime signal -- a
    sampled log of which columns are actually read in production -- it fuses
    static and runtime evidence into a confidence score per finding.

    Analyzers:
      * dead_column         -- column no code path references
      * dead_table          -- table with no model/query reference, zero rows
      * unused_index        -- non-unique index, idx_scan = 0 in pg_stat
      * duplicate_index     -- index that is a prefix of a wider index
      * missing_fk_index    -- foreign-key / *_id column with no covering index
      * always_null_column  -- pg_stats null_frac = 1.0, carries no data
      * single_value_column -- one distinct value across a large table

    Every finding carries a reclaimable-bytes estimate (from row counts) and a
    concrete fix. `generate-migration` emits a staged, reversible pair:
    ignored_columns first, remove_column after a soak. Nothing is dropped
    automatically. Columns owned by common gems (devise, paper_trail,
    activestorage, actiontext, friendly_id, audited, pg_search, ahoy_matey,
    paranoia) are whitelisted when the gem is in your bundle.

    Reporters: table, json, markdown (PR comments), SARIF 2.1.0 (GitHub code
    scanning). `scan --ci` gates only findings absent from a committed baseline.
    `trend` keeps an append-only history log for cleanup burndown. A Rails
    railtie adds rake tasks and an opt-in runtime tracker. Custom analyzers
    load through the `require:` config key.

    PostgreSQL only for now (MySQL adapter on the roadmap). Ruby >= 2.7.
  DESC
  spec.homepage = "https://github.com/aksshatt/schema_reaper"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"]      = spec.homepage
  spec.metadata["source_code_uri"]   = spec.homepage
  spec.metadata["changelog_uri"]     = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"]   = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "#{spec.homepage}#readme"
  spec.metadata["wiki_uri"]          = "#{spec.homepage}/wiki"
  spec.metadata["funding_uri"]       = "https://github.com/sponsors/aksshatt"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "prism", ">= 0.19", "< 2.0"
  spec.add_dependency "thor", "~> 1.3"

  spec.add_development_dependency "activerecord", ">= 6.1", "< 9.0"
  spec.add_development_dependency "pg", "~> 1.5"
end
