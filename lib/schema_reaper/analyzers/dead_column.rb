# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # Flags columns present in the schema but never referenced in code. When a
    # runtime usage log is supplied, its signal is fused in: a column unseen in
    # BOTH code and >= 14 observed days of runtime reaches high confidence.
    class DeadColumn < Base
      Registry.register(self)

      STATIC_ONLY_CAP  = 0.6
      RUNTIME_MIN_DAYS = 14

      def call
        schema.tables.reject { |t| config.ignore_tables.include?(t.name) }
              .flat_map { |t| dead_in(t) }
      end

      private

      def dead_in(table)
        table.columns.filter_map do |col|
          next if keep?(table, col)
          next if used?(col.name)
          next if runtime.read?(table.name, col.name)

          finding(
            type: :dead_column,
            table: table.name,
            column: col.name,
            severity: col.null ? :medium : :high,
            confidence: confidence_for(col),
            bytes_per_row: col.bytes,
            evidence: evidence_for(table, col),
            suggested_fix: "Stage removal: `self.ignored_columns += %w[#{col.name}]` on the " \
                           "model, deploy, then `remove_column :#{table.name}, :#{col.name}`."
          )
        end
      end

      def keep?(table, col)
        config.always_keep_columns.include?(col.name) ||
          config.ignored_column?(col.name) ||
          table.primary_key?(col.name) ||
          table.foreign_keys.include?(col.name) ||
          col.name.end_with?("_id", "_type") ||
          gem_reserved?(table.name, col.name)
      end

      def confidence_for(col)
        if runtime.present? && runtime.observed_days >= RUNTIME_MIN_DAYS
          col.null ? 0.9 : 0.8
        else
          base = col.null ? 0.5 : 0.4
          [base, STATIC_ONLY_CAP].min
        end
      end

      def evidence_for(table, col)
        ev = ["no `#{col.name}` reference found in scanned code"]
        ev << "column is nullable" if col.null
        ev << if runtime.present?
                "not read in #{runtime.observed_days} observed day(s) of runtime data"
              else
                "static signal only — confidence capped at #{STATIC_ONLY_CAP}"
              end
        ev << "table holds ~#{table.row_count} row(s)" if table.row_count
        ev
      end
    end
  end
end
