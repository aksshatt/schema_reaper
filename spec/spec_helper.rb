# frozen_string_literal: true

require "schema_reaper"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end

# Builds a DatabaseSchema without touching a real database.
def fake_schema(*tables)
  SchemaReaper::DatabaseSchema.new(tables: tables)
end

def fake_table(name, columns:, primary_key: "id", foreign_keys: [], indexes: [])
  cols = columns.map do |c|
    SchemaReaper::Column.new(
      name: c[:name], sql_type: c.fetch(:type, "integer"),
      null: c.fetch(:null, true), default: c[:default], bytes: c.fetch(:bytes, 4)
    )
  end
  SchemaReaper::Table.new(
    name: name, columns: cols, indexes: indexes,
    primary_key: primary_key, foreign_keys: foreign_keys
  )
end
