# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # A column that is NULL in every row (per pg_stats). The data itself says
    # it is dead, independent of code references.
    class AlwaysNullColumn < Base
      Registry.register(self)

      def call
        schema.tables.reject { |t| config.ignore_tables.include?(t.name) }
              .flat_map { |t| null_in(t) }
      end

      private

      def null_in(table)
        return [] unless table.row_count&.positive?

        table.columns.filter_map do |col|
          next unless col.always_null?
          next if config.always_keep_columns.include?(col.name)
          next if gem_reserved?(table.name, col.name)

          finding(
            type: :always_null_column,
            table: table.name,
            column: col.name,
            severity: :high,
            confidence: 0.85,
            bytes_per_row: col.bytes,
            evidence: [
              "pg_stats.null_frac = 1.0 across ~#{table.row_count} row(s)",
              "column carries no data"
            ],
            suggested_fix: "verify with `SELECT count(#{col.name}) FROM #{table.name}` " \
                           "then stage a removal"
          )
        end
      end
    end
  end
end
