# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # Two FOREIGN KEY constraints on the same columns pointing at the same
    # key of the same table, with the same ON UPDATE / ON DELETE, MATCH and
    # deferrability -- only then is either one redundant. (Same columns but a
    # different ON DELETE is not a duplicate: dropping one changes what a
    # parent delete does.) Usually a hand-written add_foreign_key layered on a
    # `t.references ..., foreign_key: true` that already made one. Each copy is
    # checked on every insert/update of the child and every delete of the
    # parent, so the extra one is pure overhead.
    class DuplicateForeignKey < Base
      Registry.register(self)

      def call
        schema.tables.reject { |t| config.ignore_tables.include?(t.name) }
              .flat_map { |t| duplicates_in(t) }
      end

      private

      def duplicates_in(table)
        table.foreign_key_constraints
             .group_by { |fk| [fk.columns, fk.references, fk.behaviour] }
             .values.select { |group| group.size > 1 }
             .flat_map { |group| redundant(table, group) }
      end

      # Keep a validated one (a NOT VALID copy doesn't check existing rows),
      # then the alphabetically first name -- Rails' fk_rails_<hash> sorts
      # ahead of hand-named ones. Report the rest.
      def redundant(table, group)
        keep, *extra = group.sort_by { |fk| [fk.validated == false ? 1 : 0, fk.name] }
        extra.map do |fk|
          finding(
            type: :duplicate_foreign_key,
            table: table.name,
            column: fk.columns.join(","),
            index: fk.name,
            severity: :low,
            confidence: 0.9,
            bytes_per_row: 0,
            evidence: [
              "#{fk.name} and #{keep.name} both constrain (#{fk.columns.join(", ")}) -> #{fk.references}"
            ],
            suggested_fix: "remove_foreign_key #{sym(table.name)}, name: :#{fk.name}"
          )
        end
      end
    end
  end
end
