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
            evidence: evidence_for(ix),
            suggested_fix: remove_index_fix(table, ix)
          )
        end
      end

      def evidence_for(index)
        [
          "pg_stat_user_indexes.idx_scan = 0 for #{index.name} (#{index.columns.join(", ")})",
          "confirm stats have not been reset recently before dropping",
          "idx_scan is per server: if read replicas serve queries, check " \
          "pg_stat_user_indexes on each replica too -- an index used only there looks unused here"
        ]
      end
    end
  end
end
