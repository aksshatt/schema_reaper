# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # A serial / IDENTITY sequence that has used up a large share of the values
    # its column can hold. When it runs out, every INSERT into the table fails.
    # The classic case is a pre-Rails-5.1 `integer` primary key, capped at
    # 2,147,483,647 even when its sequence is bigint.
    #
    # Not dead weight -- a health check, like missing_fk_index -- but it is
    # read straight from the schema scan the other analyzers already need.
    class SequenceExhaustion < Base
      Registry.register(self)

      WARN_AT = 0.5
      HIGH_AT = 0.75

      def call
        schema.sequences.filter_map do |seq|
          next if config.ignore_tables.include?(seq.table)
          next if seq.used_fraction < WARN_AT

          finding_for(seq)
        end
      end

      private

      def finding_for(seq)
        pct = (seq.used_fraction * 100).round(1)
        finding(
          type: :sequence_exhaustion,
          table: seq.table,
          column: seq.column,
          severity: seq.used_fraction >= HIGH_AT ? :high : :medium,
          confidence: 0.95, # read from the database, not inferred
          bytes_per_row: 0,
          evidence: [
            "#{seq.name} is at #{seq.last_value} of #{seq.max_value} (#{pct}%) " \
            "for #{seq.column_type} column #{seq.column}",
            "INSERTs into #{seq.table} fail once it is exhausted"
          ],
          suggested_fix: fix_for(seq)
        )
      end

      def fix_for(seq)
        return "the sequence itself is near its MAXVALUE -- raise it with ALTER SEQUENCE" if seq.column_type == "bigint"

        "change_column #{sym(seq.table)}, :#{seq.column}, :bigint  " \
          "(rewrites the table under an exclusive lock -- plan for it on a large table)"
      end
    end
  end
end
