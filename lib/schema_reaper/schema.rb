# frozen_string_literal: true

module SchemaReaper
  # Plain-data representation of the database, produced by an introspector.
  # No ActiveRecord objects leak past this boundary.
  Column = Struct.new(:name, :sql_type, :null, :default, :bytes, keyword_init: true)
  Index  = Struct.new(:name, :columns, :unique, keyword_init: true)

  Table = Struct.new(:name, :columns, :indexes, :primary_key, :foreign_keys, keyword_init: true) do
    def column_names = columns.map(&:name)
  end

  DatabaseSchema = Struct.new(:tables, keyword_init: true) do
    def table(name) = tables.find { |t| t.name == name }
  end
end
