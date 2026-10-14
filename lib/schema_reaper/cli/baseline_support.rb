# frozen_string_literal: true

require "date"

module SchemaReaper
  class CLI < Thor
    # Output helpers for `baseline` and the `scan --ci` gate.
    module BaselineSupport
      private

      def report_pruned(dropped)
        return console.ok("nothing to prune -- every baseline entry still occurs") if dropped.empty?

        console.ok("dropped #{dropped.size} resolved entr#{dropped.size == 1 ? "y" : "ies"}")
        dropped.each { |id| console.info("  #{id}") }
      end

      def parse_date(value)
        return nil unless value

        Date.iso8601(value)
      rescue ArgumentError
        console.problem("--expires must be a date like 2027-01-31, got #{value.inspect}")
        exit 1
      end

      def warn_expired(expired, findings)
        current = findings.map(&:id)
        live = expired.select { |e| current.include?(e.id) }
        return if live.empty?

        console.notice("#{live.size} baseline entr#{live.size == 1 ? "y has" : "ies have"} expired and count as new:")
        live.each { |e| console.info("  #{e.id} (expired #{e.expires_on}#{" -- #{e.reason}" if e.reason})") }
      end
    end
  end
end
