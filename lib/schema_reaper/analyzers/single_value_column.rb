# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # A column holding exactly one distinct value across a non-trivial number of
    # rows carries no information — usually a flag that was never toggled or a
    # backfill that set everyone the same.
    class SingleValueColumn < Base
      Registry.register(self)

      MIN_ROWS = 500

      def call
        schema.tables.reject { |t| config.ignore_tables.include?(t.name) }
              .flat_map { |t| flat_in(t) }
      end

      private

      def flat_in(table)
        return [] unless table.row_count.to_i >= MIN_ROWS

        table.columns.filter_map do |col|
          next unless col.single_value?
          next if table.primary_key?(col.name)
          next if config.always_keep_columns.include?(col.name)
          next if gem_reserved?(table.name, col.name)

          finding(
            type: :single_value_column,
            table: table.name,
            column: col.name,
            severity: :low,
            confidence: 0.6,
            bytes_per_row: col.bytes,
            evidence: [
              "pg_stats.n_distinct = 1 across ~#{table.row_count} row(s)",
              "column has the same value in every row"
            ],
            suggested_fix: "confirm the value is not a meaningful default before removing"
          )
        end
      end
    end
  end
end
