# frozen_string_literal: true

require_relative "schema_reaper/version"
require_relative "schema_reaper/config"
require_relative "schema_reaper/finding"
require_relative "schema_reaper/schema"
require_relative "schema_reaper/runtime"
require_relative "schema_reaper/gem_awareness"
require_relative "schema_reaper/introspect/postgres"
require_relative "schema_reaper/static/scanner"
require_relative "schema_reaper/analyzers/base"
require_relative "schema_reaper/analyzers/registry"
require_relative "schema_reaper/analyzers/dead_column"
require_relative "schema_reaper/analyzers/dead_table"
require_relative "schema_reaper/analyzers/unused_index"
require_relative "schema_reaper/analyzers/duplicate_index"
require_relative "schema_reaper/analyzers/missing_fk_index"
require_relative "schema_reaper/analyzers/always_null_column"
require_relative "schema_reaper/analyzers/single_value_column"
require_relative "schema_reaper/reporters/bytes"
require_relative "schema_reaper/reporters/ansi"
require_relative "schema_reaper/reporters/console"
require_relative "schema_reaper/reporters/table"
require_relative "schema_reaper/reporters/trend"
require_relative "schema_reaper/reporters/json"
require_relative "schema_reaper/reporters/markdown"
require_relative "schema_reaper/reporters/sarif"
require_relative "schema_reaper/baseline"
require_relative "schema_reaper/history"
require_relative "schema_reaper/migration_generator"
require_relative "schema_reaper/runner"
require_relative "schema_reaper/alert_config"
require_relative "schema_reaper/notifier"
require_relative "schema_reaper/scan_job" if defined?(ActiveJob::Base)
require_relative "schema_reaper/railtie" if defined?(Rails::Railtie)

# Finds columns, indexes and tables that a Rails/ActiveRecord app no longer
# uses, then helps remove them safely. See {Runner} and the CLI.
module SchemaReaper
  class Error < StandardError; end

  # Autoloaded, not required: Mailer picks its superclass (the host app's
  # ApplicationMailer, when there is one) at the moment it is defined. At
  # gem-require time -- Bundler.require, early in boot -- the app's own
  # autoloader isn't set up yet, so ApplicationMailer can never be seen and
  # Mailer would always fall back to ActionMailer::Base, silently losing the
  # app's `default from:`. Deferring to first reference (when a report is
  # actually sent, long after boot) fixes that, and still lets a worker
  # process resolve "SchemaReaper::Mailer" by name when it deserializes the
  # mail delivery job.
  autoload :Mailer, File.expand_path("schema_reaper/mailer", __dir__)

  REPORTERS = {
    "table" => Reporters::Table,
    "json" => Reporters::Json,
    "markdown" => Reporters::Markdown,
    "sarif" => Reporters::Sarif
  }.freeze

  def self.reporter(name)
    REPORTERS.fetch(name, Reporters::Table)
  end
end
