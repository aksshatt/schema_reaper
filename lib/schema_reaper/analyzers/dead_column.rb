# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # Flags columns present in the schema but never referenced anywhere in the
    # scanned codebase. Static signal only in v0.1 -> capped confidence.
    class DeadColumn < Base
      Registry.register(self)

      MAX_STATIC_CONFIDENCE = 0.6

      def call
        schema.tables.reject { |t| config.ignore_tables.include?(t.name) }
              .flat_map { |t| dead_in(t) }
      end

      private

      def dead_in(table)
        table.columns.filter_map do |col|
          next if keep?(table, col)
          next if used?(col.name)

          Finding.new(
            type: :dead_column,
            table: table.name,
            column: col.name,
            severity: severity_for(col),
            confidence: confidence_for(table, col),
            bytes_per_row: col.bytes,
            evidence: evidence_for(table, col),
            suggested_fix: "Stage removal: add `#{table.name}` to ignored_columns, " \
                           "deploy, then `remove_column :#{table.name}, :#{col.name}`."
          )
        end
      end

      def keep?(table, col)
        config.always_keep_columns.include?(col.name) ||
          config.ignored_column?(col.name) ||
          col.name == table.primary_key ||
          table.foreign_keys.include?(col.name) ||
          col.name.end_with?("_id", "_type") # associations resolved indirectly
      end

      def severity_for(col)
        col.null == false && col.default.nil? ? :high : :medium
      end

      def confidence_for(_table, col)
        base = 0.4
        base += 0.1 if col.null # nullable & unused -> more likely truly dead
        [base, MAX_STATIC_CONFIDENCE].min
      end

      def evidence_for(_table, col)
        [
          "no identifier, symbol or string literal `#{col.name}` found in scan paths",
          ("column is nullable" if col.null)
        ].compact
      end
    end
  end
end
