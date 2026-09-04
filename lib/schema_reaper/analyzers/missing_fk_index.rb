# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # A foreign-key column with no index: every parent delete/update scans the
    # child table. This is a repo-health nag, not dead weight.
    class MissingFkIndex < Base
      Registry.register(self)

      def call
        schema.tables.reject { |t| config.ignore_tables.include?(t.name) }
              .flat_map { |t| missing_in(t) }
      end

      private

      def missing_in(table)
        fk_columns(table).filter_map do |col|
          next if indexed?(table, col)

          finding(
            type: :missing_fk_index,
            table: table.name,
            column: col,
            severity: :medium,
            confidence: 0.9,
            bytes_per_row: 0,
            evidence: ["#{col} is a foreign key with no covering index"],
            suggested_fix: "add_index :#{table.name}, :#{col}"
          )
        end
      end

      def fk_columns(table)
        (table.foreign_keys + table.column_names.grep(/_id\z/)).uniq
      end

      def indexed?(table, col)
        table.indexes.any? { |ix| ix.columns.first == col }
      end
    end
  end
end
