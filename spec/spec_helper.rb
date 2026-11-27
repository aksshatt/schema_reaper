# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  enable_coverage :branch
end

# Loaded before schema_reaper so its ActiveJob-/ActionMailer-gated files
# (ScanJob, Mailer -- see lib/schema_reaper.rb) actually get required. Both
# guards are checked once, at this require, not per-spec.
# ActiveSupport < 7.1 references ::Logger without requiring it, which breaks
# under concurrent-ruby >= 1.3.5 (it stopped loading logger itself).
require "logger"
require "active_job"
require "action_mailer"
ActiveJob::Base.queue_adapter = :test

require "schema_reaper"
# Mailer is autoloaded and picks its superclass on first reference. Resolve
# it now, while no spec has defined a throwaway ::ApplicationMailer (the
# generator specs do), so every example sees the same class.
SchemaReaper.const_get(:Mailer)

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }

  # The scan cache is on by default and would litter spec/fixtures (and the
  # repo root) with .schema_reaper/scan_cache.json. Specs that exercise it
  # opt back in with `scan_cache: true` metadata.
  config.before do |example|
    next if example.metadata[:scan_cache]

    allow_any_instance_of(SchemaReaper::Config).to receive(:scan_cache).and_return(nil)
  end
end

# Builds a DatabaseSchema without touching a real database. index_scan_total
# defaults to nil, meaning "stats unknown" -- analyzers treat that as usable.
def fake_schema(*tables, index_scan_total: nil)
  SchemaReaper::DatabaseSchema.new(tables: tables, index_scan_total: index_scan_total)
end

def fake_column(attrs)
  SchemaReaper::Column.new(
    name: attrs.fetch(:name),
    sql_type: attrs.fetch(:type, "integer"),
    null: attrs.fetch(:null, true),
    default: attrs[:default],
    bytes: attrs.fetch(:bytes, 4),
    null_fraction: attrs[:null_fraction],
    distinct_values: attrs[:distinct_values]
  )
end

def fake_index(attrs)
  SchemaReaper::Index.new(
    name: attrs.fetch(:name),
    columns: Array(attrs.fetch(:columns)),
    unique: attrs.fetch(:unique, false),
    primary: attrs.fetch(:primary, false),
    partial: attrs.fetch(:partial, false),
    scans: attrs[:scans]
  )
end

def fake_table(name, columns:, primary_key: "id", foreign_keys: [], indexes: [], row_count: nil)
  SchemaReaper::Table.new(
    name: name,
    columns: columns.map { |c| fake_column(c) },
    indexes: indexes.map { |i| fake_index(i) },
    primary_key: primary_key,
    foreign_keys: foreign_keys,
    row_count: row_count
  )
end

def runtime_report(accessed: [], observed_days: 0)
  SchemaReaper::Runtime::Report.new(
    accessed: accessed.to_set, observed_days: observed_days
  )
end

def context_for(schema:, used: [], runtime: nil, gem_columns: {}, gem_owned_tables: Set.new, config: nil)
  SchemaReaper::Analyzers::Context.new(
    schema: schema,
    used_tokens: used.to_set,
    runtime: runtime,
    gem_columns: gem_columns,
    gem_owned_tables: gem_owned_tables,
    config: config || SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.dup)
  )
end
