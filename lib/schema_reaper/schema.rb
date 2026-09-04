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
    def always_null?
      null_fraction && null_fraction >= 1.0
    end

    # true when the column holds exactly one distinct non-null value
    def single_value?
      distinct_values == 1
    end
  end

  Index = Struct.new(:name, :columns, :unique, :primary, :scans, keyword_init: true) do
    def covers?(other)
      columns.first(other.columns.length) == other.columns
    end
  end

  Table = Struct.new(
    :name, :columns, :indexes, :primary_key, :foreign_keys, :row_count,
    keyword_init: true
  ) do
    def column_names
      columns.map(&:name)
    end

    def column(name)
      columns.find { |c| c.name == name }
    end

    def index_on(cols)
      indexes.find { |i| i.columns == Array(cols) }
    end

    # primary_key may be a single name or, for a composite key, the ordered
    # list. Array() accepts both so introspectors that still return one name
    # keep working.
    def primary_key_columns
      Array(primary_key)
    end

    def primary_key?(column_name)
      primary_key_columns.include?(column_name)
    end
  end

  DatabaseSchema = Struct.new(:tables, :index_scan_total, keyword_init: true) do
    def table(name)
      tables.find { |t| t.name == name }
    end

    def index_count
      tables.sum { |t| t.indexes.size }
    end

    # pg_stat counters are cumulative since the last reset, so idx_scan = 0 only
    # means "unused" if the database has served enough traffic for a used index
    # to have registered. A database that has taken real queries scans its
    # indexes far more than once each; below that we are looking at a fresh,
    # restored, or just-reset cluster where every zero is an artifact.
    #
    # nil means the introspector did not report a total -- assume stats are
    # usable rather than silently dropping findings.
    def query_history?
      return true if index_scan_total.nil?

      index_scan_total >= index_count
    end
  end
end
