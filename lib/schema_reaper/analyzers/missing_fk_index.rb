# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # A foreign-key column with no index: every parent delete/update scans the
    # child table. This is a repo-health nag, not dead weight.
    #
    # A `*_id` column paired with a `*_type` column is a polymorphic
    # association. Rails never queries the id without the type, so the index
    # that matters is the composite `(type, id)` -- a bare index on the id
    # alone would go unused.
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
          next if empty_column?(table, col) # never advise indexing a column with no data

          type_col = polymorphic_type_for(table, col)
          next if type_col && polymorphic_indexed?(table, type_col, col)

          finding_for(table, col, type_col)
        end
      end

      # A foreign-key column that is NULL in every row of a non-empty table:
      # an index would be pointless, and another analyzer already flags it as
      # dead. Leave that finding to speak for the column.
      def empty_column?(table, col)
        return false unless table.row_count.to_i.positive?

        table.column(col)&.always_null? || false
      end

      def finding_for(table, col, type_col)
        finding(
          type: :missing_fk_index,
          table: table.name,
          column: col,
          severity: :medium,
          confidence: 0.9,
          bytes_per_row: 0,
          evidence: [evidence_for(col, type_col)],
          suggested_fix: fix_for(table, col, type_col)
        )
      end

      def evidence_for(col, type_col)
        return "#{col} is a foreign key with no covering index" unless type_col

        "#{col} is a polymorphic association with #{type_col} and has no (#{type_col}, #{col}) index"
      end

      def fix_for(table, col, type_col)
        return "add_index :#{table.name}, :#{col}" unless type_col

        "add_index :#{table.name}, %i[#{type_col} #{col}]"
      end

      def fk_columns(table)
        (table.foreign_keys + table.column_names.grep(/_id\z/)).uniq
      end

      def indexed?(table, col)
        table.indexes.any? { |ix| ix.columns.first == col }
      end

      # The `*_type` column paired with a polymorphic `*_id`, when present.
      def polymorphic_type_for(table, col)
        return nil unless col.end_with?("_id")

        type_col = "#{col[0..-4]}_type"
        table.column_names.include?(type_col) ? type_col : nil
      end

      # Rails writes these as add_index :table, %i[thing_type thing_id], so the
      # pair leads the index; trailing columns (version, name, ...) are fine.
      def polymorphic_indexed?(table, type_col, id_col)
        table.indexes.any? { |ix| ix.columns.first(2) == [type_col, id_col] }
      end
    end
  end
end
