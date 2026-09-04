# frozen_string_literal: true

require_relative "schema_reaper/version"
require_relative "schema_reaper/config"
require_relative "schema_reaper/finding"
require_relative "schema_reaper/schema"
require_relative "schema_reaper/introspect/postgres"
require_relative "schema_reaper/static/scanner"
require_relative "schema_reaper/analyzers/base"
require_relative "schema_reaper/analyzers/registry"
require_relative "schema_reaper/analyzers/dead_column"
require_relative "schema_reaper/reporters/table"
require_relative "schema_reaper/reporters/json"
require_relative "schema_reaper/baseline"
require_relative "schema_reaper/migration_generator"
require_relative "schema_reaper/runner"

module SchemaReaper
  class Error < StandardError; end
end
