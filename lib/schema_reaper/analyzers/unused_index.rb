# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # Indexes with zero scans in pg_stat_user_indexes. Requires stats to be
    # meaningful (a freshly reset stat table would false-positive), so findings
    # stay medium confidence and note the caveat.
    class UnusedIndex < Base
      Registry.register(self)

      def call
        # Without query history every idx_scan is 0, so this analyzer would
        # report every non-unique index in the database. Report nothing rather
        # than burying the other analyzers' findings under that noise.
        return [] unless schema.query_history?

        schema.tables.reject { |t| config.ignore_tables.include?(t.name) }
              .flat_map { |t| unused_in(t) }
      end

      private

      def unused_in(table)
        table.indexes.filter_map do |ix|
          next if ix.primary || ix.unique # keep constraint-backing indexes
          next if ix.scans.nil? # no stats available
          next unless ix.scans.zero?

          finding(
            type: :unused_index,
            table: table.name,
            index: ix.name,
            column: ix.columns.join(","),
            severity: :medium,
            confidence: 0.55,
            bytes_per_row: 0,
            evidence: [
              "pg_stat_user_indexes.idx_scan = 0 for #{ix.name} (#{ix.columns.join(", ")})",
              "confirm stats have not been reset recently before dropping"
            ],
            suggested_fix: "remove_index :#{table.name}, name: :#{ix.name}  " \
                           "(use algorithm: :concurrently in production)"
          )
        end
      end
    end
  end
end
