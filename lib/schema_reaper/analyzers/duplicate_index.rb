# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # An index whose column list is a leading prefix of another index on the
    # same table is redundant (the wider index serves both).
    class DuplicateIndex < Base
      Registry.register(self)

      def call
        schema.tables.reject { |t| config.ignore_tables.include?(t.name) }
              .flat_map { |t| dupes_in(t) }
      end

      private

      def dupes_in(table)
        non_pk = table.indexes.reject(&:primary)
        non_pk.filter_map do |ix|
          covering = non_pk.find { |o| o != ix && !o.unique && o.covers?(ix) && o.columns != ix.columns }
          next unless covering

          finding(
            type: :duplicate_index,
            table: table.name,
            index: ix.name,
            column: ix.columns.join(","),
            severity: :low,
            confidence: 0.8,
            bytes_per_row: 0,
            evidence: [
              "#{ix.name} (#{ix.columns.join(", ")}) is a prefix of " \
              "#{covering.name} (#{covering.columns.join(", ")})"
            ],
            suggested_fix: "remove_index :#{table.name}, name: :#{ix.name}"
          )
        end
      end
    end
  end
end
