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
          next if ignored_column?(col.name)
          next if gem_reserved?(table.name, col.name)

          finding(
            type: :single_value_column,
            table: table.name,
            column: col.name,
            severity: :low,
            confidence: sampled_stats?(table) ? 0.5 : 0.6,
            bytes_per_row: col.bytes,
            evidence: evidence_for(table, col),
            suggested_fix: "confirm the value is not a meaningful default before removing"
          )
        end
      end

      # n_distinct counts non-null values only, so "one value" and "the same
      # value in every row" are different claims when some rows are NULL.
      def evidence_for(table, col)
        nulls = col.null_fraction.to_f
        ev = ["pg_stats.n_distinct = 1 across ~#{table.row_count} row(s)"]
        ev << if nulls.positive?
                "one distinct non-null value; #{(nulls * 100).round(1)}% of rows are NULL"
              else
                "column has the same value in every row"
              end
        ev << "estimated from a #{STATS_SAMPLE_ROWS}-row ANALYZE sample" if sampled_stats?(table)
        ev
      end
    end
  end
end
