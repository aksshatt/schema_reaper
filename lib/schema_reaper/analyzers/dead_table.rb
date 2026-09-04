# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # A table with no model reference in code, no runtime access, and (if known)
    # zero rows. Reported as one finding for the whole table.
    class DeadTable < Base
      Registry.register(self)

      # Enough of Rails' inflector for table names. A wrong guess only costs a
      # redundant lookup -- every form is checked and any hit counts -- so the
      # rules stay small rather than trying to be complete.
      SINGULAR_RULES = [
        [/ies\z/, "y"],               # activities -> activity
        [/(ss|sh|ch|x|z)es\z/, '\1'], # addresses  -> address, boxes -> box
        [/s\z/, ""]                   # employees  -> employee
      ].freeze

      def call
        schema.tables.reject { |t| ignored?(t) }.filter_map { |t| dead(t) }
      end

      private

      def ignored?(table)
        config.ignore_tables.include?(table.name) ||
          table.name.start_with?("active_storage_", "action_text_", "action_mailbox_")
      end

      def dead(table)
        return if referenced?(table)
        return if runtime.accessed.any? { |k| k.start_with?("#{table.name}.") }

        finding(
          type: :dead_table,
          table: table.name,
          column: nil,
          severity: :high,
          confidence: confidence_for(table),
          bytes_per_row: table.columns.sum(&:bytes),
          evidence: evidence_for(table),
          suggested_fix: "confirm no external consumer, then `drop_table :#{table.name}`"
        )
      end

      # Match the table name and its singular/camelized model form.
      def referenced?(table)
        singular = singularize(table.name)
        forms = [table.name, singular, camelize(table.name), camelize(singular)]
        return true if forms.any? { |form| used?(form) }

        embedded_in_identifier?(table.name)
      end

      def singularize(name)
        rule = SINGULAR_RULES.find { |pattern, _| name.match?(pattern) }
        rule ? name.sub(rule[0], rule[1]) : name
      end

      # Route helpers, i18n keys and CSS selectors bury a table name inside a
      # longer identifier (admin_crm_activities_path), which the scanner
      # tokenises as a single word. Count the name as referenced when it appears
      # as a whole underscore-delimited run inside some token -- `logs` must not
      # match `catalogs`, but must match `audit_logs_path`.
      def embedded_in_identifier?(name)
        pattern = /(?:\A|_)#{Regexp.escape(name)}(?:_|\z)/
        ctx.used_tokens.any? { |token| token.include?(name) && pattern.match?(token) }
      end

      def confidence_for(table)
        return 0.5 if table.row_count.nil?

        table.row_count.zero? ? 0.85 : 0.4
      end

      def evidence_for(table)
        ev = ["no model or query reference to `#{table.name}` in scanned code"]
        ev << "runtime data shows no access" if runtime.present?
        ev << "table holds ~#{table.row_count} row(s)" unless table.row_count.nil?
        ev
      end

      def camelize(str)
        str.split("_").map(&:capitalize).join
      end
    end
  end
end
