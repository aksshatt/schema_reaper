# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # An index whose column list is a leading prefix of another index on the
    # same table is redundant (the wider index serves both), and two indexes
    # with identical column lists are redundant with each other.
    class DuplicateIndex < Base
      Registry.register(self)

      def call
        schema.tables.reject { |t| config.ignore_tables.include?(t.name) }
              .flat_map { |t| dupes_in(t) }
      end

      private

      # A partial index only exists for rows matching its WHERE clause and is
      # usually there on purpose (a smaller, faster index for one condition),
      # so it is excluded entirely rather than reasoned about: not a
      # candidate for removal, and not a stand-in for a full index either.
      # Comparing WHERE clauses for implication is out of scope here, and a
      # wrong guess in either direction is a real index gone from production.
      def dupes_in(table)
        non_pk = table.indexes.reject { |index| index.primary || index.partial? }
        by_columns = non_pk.group_by(&:columns)
        non_pk.filter_map { |index| finding_for(table, index, non_pk, by_columns) }
      end

      def finding_for(table, index, non_pk, by_columns)
        covering = covering_for(index, non_pk, by_columns)
        return unless covering

        finding(
          type: :duplicate_index,
          table: table.name,
          index: index.name,
          column: index.columns.join(","),
          severity: :low,
          confidence: 0.8,
          bytes_per_row: 0,
          evidence: [evidence_for(index, covering)],
          suggested_fix: "remove_index :#{table.name}, name: :#{index.name}"
        )
      end

      # Two indexes with the same column list have no natural wider/narrower
      # direction, so comparing them pairwise would have each flag the other --
      # applying both suggested fixes would then drop the column pair
      # entirely. Instead, one designated survivor per exact-column group is
      # chosen once; every other member of the group is redundant against it,
      # and the survivor itself is only checked against a genuinely wider
      # prefix elsewhere on the table.
      def covering_for(index, non_pk, by_columns)
        peers = by_columns[index.columns]
        return prefix_covering_for(index, non_pk) if peers.size == 1

        survivor = survivor_of(peers)
        return survivor unless survivor == index

        prefix_covering_for(index, non_pk)
      end

      # Keep a unique index over a non-unique one -- it enforces a guarantee
      # the others don't -- breaking further ties by name for a stable,
      # order-independent choice.
      def survivor_of(peers)
        unique_peers = peers.select(&:unique)
        (unique_peers.empty? ? peers : unique_peers).min_by(&:name)
      end

      def prefix_covering_for(index, non_pk)
        non_pk.find do |o|
          o != index && o.columns != index.columns && o.covers?(index) && safe_to_drop?(index, against: o)
        end
      end

      # A wider index does not make a narrower prefix unique: unique (a, b)
      # says nothing about whether a alone is unique. So a unique index is
      # only safe to drop in favour of another index that is itself unique on
      # that exact same column list -- never a merely-wider or non-unique one.
      def safe_to_drop?(index, against:)
        !index.unique || (against.unique && against.columns == index.columns)
      end

      def evidence_for(index, covering)
        relation = covering.columns == index.columns ? "duplicates" : "is a prefix of"
        "#{index.name} (#{index.columns.join(", ")}) #{relation} " \
          "#{covering.name} (#{covering.columns.join(", ")})"
      end
    end
  end
end
