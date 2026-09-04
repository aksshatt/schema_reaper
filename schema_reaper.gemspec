# frozen_string_literal: true

require_relative "lib/schema_reaper/version"

Gem::Specification.new do |spec|
  spec.name = "schema_reaper"
  spec.version = SchemaReaper::VERSION
  spec.authors = %w[aksshatt mitkush]
  spec.email = ["akshatpegwar5@gmail.com", "mitanshukushwah@gmail.com"]

  spec.summary = "Find and safely remove schema dead-weight in Rails + PostgreSQL apps."
  spec.description =
    "schema_reaper finds schema dead-weight in Rails/ActiveRecord + PostgreSQL apps: " \
    "dead columns and tables, unused, duplicate and missing foreign-key indexes, and " \
    "always-NULL or single-value columns. It cross-references the live schema and pg_stats " \
    "against a static scan of your code, with an optional production runtime signal for " \
    "higher confidence. Each finding is scored, carries a reclaimable-bytes estimate, and " \
    "ships with a staged, reversible migration. Reporters for terminal, JSON, Markdown and " \
    "SARIF; a CI baseline gate; a trend log; a Rails railtie. PostgreSQL only for now; " \
    "Ruby >= 2.7. See the README for full usage."
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
