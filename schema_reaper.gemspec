# frozen_string_literal: true

require_relative "lib/schema_reaper/version"

Gem::Specification.new do |spec|
  spec.name = "schema_reaper"
  spec.version = SchemaReaper::VERSION
  spec.authors = ["Rahul Dwivedi"]
  spec.email = ["rrahuldwivedi01@gmail.com"]

  spec.summary = "Find dead columns, unused indexes and schema dead-weight in Rails/ActiveRecord apps."
  spec.description = <<~DESC
    schema_reaper scans your database schema and your codebase to surface columns,
    indexes and tables that are no longer referenced. It scores findings by
    confidence, estimates the disk they reclaim, and generates safe staged
    migrations to remove them. Static analysis in v0.1; runtime + pg_stat signal
    fusion on the roadmap.
  DESC
  spec.homepage = "https://github.com/rrahuldwivedi01/schema_reaper"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
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

  spec.add_dependency "prism", ">= 0.19"
  spec.add_dependency "thor", "~> 1.3"

  spec.add_development_dependency "activerecord", ">= 6.1"
  spec.add_development_dependency "pg", "~> 1.5"
end
