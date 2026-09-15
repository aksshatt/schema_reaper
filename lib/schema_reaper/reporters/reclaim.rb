# frozen_string_literal: true

require_relative "bytes"

module SchemaReaper
  module Reporters
    # Turns a set of findings' reclaimable-bytes into a human sentence, and a
    # single finding's into a table cell. Shared by every reporter that states
    # a reclaim total in prose, so the answer cannot drift between formats --
    # which is how the terminal report learned to distinguish "no bytes" from
    # "no idea" while the Markdown report kept treating them as the same 0.
    module Reclaim
      module_function

      # A row count is required for a byte estimate, and pg reports
      # reltuples = -1 for a table that has never been analysed. Printing 0.0 B
      # for an unknown reads as "nothing to gain here", a different claim.
      def summary(findings)
        total = findings.sum(&:reclaimable_bytes)
        return "~#{Bytes.human(total)} reclaimable" if total.positive?
        return nil unless unmeasured?(findings)

        "reclaim estimate unavailable — run ANALYZE to populate table statistics"
      end

      # True when some finding's byte estimate is unknown rather than zero.
      # bytes_per_row.zero? findings (missing_fk_index, duplicate_index -- they
      # add or drop an index, not data) always reclaim 0 regardless of row
      # count, so an unknown row count does not make their answer unmeasured.
      def unmeasured?(findings)
        findings.any? { |f| f.bytes_per_row.to_i.positive? && !f.reclaim_known? }
      end

      # Per-finding cell for a table row: the human size, or a note that it is
      # not known, using the same bytes_per_row-zero exception as summary.
      def cell(finding)
        return Bytes.human(finding.reclaimable_bytes) if measured?(finding)

        "unknown"
      end

      def measured?(finding)
        finding.bytes_per_row.to_i.zero? || finding.reclaim_known?
      end
    end
  end
end
