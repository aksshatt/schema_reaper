# frozen_string_literal: true

module SchemaReaper
  # Plain-data representation of the database, produced by an introspector.
  # No ActiveRecord objects leak past this boundary.
  Column = Struct.new(
    :name, :sql_type, :null, :default, :bytes,
    :distinct_values, :null_fraction,
    keyword_init: true
  ) do
    # true when every row holds NULL (pg_stats null_frac == 1)
    def always_null? = null_fraction && null_fraction >= 1.0

    # true when the column holds exactly one distinct non-null value
    def single_value? = distinct_values == 1
  end

  Index = Struct.new(:name, :columns, :unique, :primary, :scans, keyword_init: true) do
    def covers?(other) = columns.first(other.columns.length) == other.columns
  end

  Table = Struct.new(
    :name, :columns, :indexes, :primary_key, :foreign_keys, :row_count,
    keyword_init: true
  ) do
    def column_names = columns.map(&:name)
    def column(name) = columns.find { |c| c.name == name }
    def index_on(cols) = indexes.find { |i| i.columns == Array(cols) }
  end

  DatabaseSchema = Struct.new(:tables, keyword_init: true) do
    def table(name) = tables.find { |t| t.name == name }
  end
end
