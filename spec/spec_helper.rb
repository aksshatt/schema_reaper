# frozen_string_literal: true

require "schema_reaper"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
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

def context_for(schema:, used: [], runtime: nil, gem_columns: {}, config: nil)
  SchemaReaper::Analyzers::Context.new(
    schema: schema,
    used_tokens: used.to_set,
    runtime: runtime,
    gem_columns: gem_columns,
    config: config || SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.dup)
  )
end
