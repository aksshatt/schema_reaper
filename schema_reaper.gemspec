# frozen_string_literal: true

require_relative "lib/schema_reaper/version"

Gem::Specification.new do |spec|
  spec.name = "schema_reaper"
  spec.version = SchemaReaper::VERSION
  spec.authors = %w[aksshatt mitkush]
  spec.email = ["akshatpegwar5@gmail.com", "mitanshukushwah@gmail.com"]

  spec.summary = "Find and safely remove schema dead-weight in Rails + PostgreSQL apps."
  spec.description = <<~DESC.strip
    schema_reaper scans a Rails + PostgreSQL app for schema debt that's easy to accumulate and hard to find by hand.

    It checks your live database against your codebase and flags three kinds of problems: things nothing references anymore (dead columns and dead tables), index trouble (indexes nobody queries, indexes made redundant by a wider index that already covers them, and foreign-key columns with no index at all), and degenerate data (columns that are always NULL, or hold the exact same value in every row).

    Every finding comes with a confidence score, an estimate of the disk space removing it would reclaim, and a concrete fix. For a column, that's a two-step migration: stop reading it first, then drop it once you've confirmed nothing broke. An optional runtime tracker can sample real production traffic to raise confidence further, for cases a static code scan alone can't settle.

    Reports come as a colored terminal summary, JSON, Markdown for a PR comment, or SARIF for GitHub code scanning -- plus a CI baseline gate and a trend log to track progress release over release.

    PostgreSQL only for now. Requires Ruby 2.7 or later. Full usage is in the README.
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
