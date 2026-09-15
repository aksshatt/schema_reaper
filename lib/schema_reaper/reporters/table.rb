# frozen_string_literal: true

require_relative "bytes"
require_relative "ansi"

module SchemaReaper
  module Reporters
    # Human-readable terminal report: a summary line, findings grouped by table
    # and sorted by confidence, then a severity/type tally. Colour is used only
    # on an interactive terminal (see Ansi).
    class Table
      SEV_ORDER = { high: 0, medium: 1, low: 2 }.freeze

      def initialize(findings, io: $stdout, color: nil)
        @findings = findings
        @io = io
        @a = Ansi.new(io: io, enabled: color)
      end

      def render
        return render_clean if @findings.empty?

        header
        grouped.each { |table, group| render_table(table, group) }
        footer
      end

      private

      def render_clean
        @io.puts @a.paint("  ✓ no findings — schema is lean", :green, :bold)
      end

      def header
        @io.puts
        @io.puts "  #{@a.paint("schema_reaper", :bold)}  #{@a.paint(scope_text, :bold)}"
        @io.puts "  #{@a.paint(type_breakdown, :dim)}"
        @io.puts "  #{@a.paint(reclaim_text, :dim)}" if reclaim_text
        @io.puts
      end

      def scope_text
        tables = @findings.map(&:table).uniq.size
        "#{@findings.size} finding#{"s" unless @findings.size == 1} across " \
          "#{tables} table#{"s" unless tables == 1}"
      end

      def type_breakdown
        @findings.group_by(&:type).transform_values(&:size)
                 .sort_by { |_t, n| -n }
                 .map { |t, n| "#{t} #{n}" }.join(" · ")
      end

      # A reclaim estimate needs a row count, and pg reports reltuples = -1 for
      # a table it has never analysed. Printing 0.0 B for an unknown reads as
      # "nothing to gain here", which is a different claim entirely.
      def reclaim_text
        return "~#{Bytes.human(total_reclaimable)} reclaimable" if total_reclaimable.positive?
        return nil unless unmeasured?

        "reclaim estimate unavailable — run ANALYZE to populate table statistics"
      end

      def unmeasured?
        @findings.any? { |f| f.bytes_per_row.to_i.positive? && !f.reclaim_known? }
      end

      def grouped
        @findings
          .sort_by { |f| [-f.confidence, SEV_ORDER.fetch(f.severity, 9)] }
          .group_by(&:table)
      end

      def render_table(table, group)
        @io.puts "  #{@a.paint(table, :bold, :magenta)}"
        group.each { |f| render_finding(f) }
        @io.puts
      end

      def render_finding(finding)
        @io.puts finding_head(finding)
        @io.puts "           #{@a.paint(evidence_line(finding), :dim)}"
        fix = "→ #{finding.suggested_fix}"
        @io.puts "           #{@a.paint(fix, :green)}"
      end

      def finding_head(finding)
        pct = (finding.confidence * 100).round
        bar = @a.confidence_bar(finding.confidence, finding.severity)
        sev = @a.severity(finding.severity, format("%-6s", finding.severity))
        label = finding.target_label
        type_text = label ? format("%-19s", finding.type) : finding.type.to_s

        head = format("    %s %3d%%  %s  %s", bar, pct, sev, @a.paint(type_text, :bold))
        head << "  #{label}" if label
        head << rjust_bytes(finding)
        head
      end

      def rjust_bytes(finding)
        return "" unless finding.reclaimable_bytes.positive?

        human = Bytes.human(finding.reclaimable_bytes)
        "  #{@a.paint(human, :dim)}"
      end

      def evidence_line(finding)
        finding.evidence.join(" · ")
      end

      def footer
        by_sev = @findings.group_by(&:severity)
        tally = SEV_ORDER.keys.filter_map do |sev|
          n = by_sev[sev]&.size
          @a.severity(sev, "#{sev} #{n}") if n
        end.join("   ")

        @io.puts "  #{tally}"
        @io.puts "  #{@a.paint(type_breakdown, :dim)}"
      end

      def total_reclaimable
        @findings.sum(&:reclaimable_bytes)
      end
    end
  end
end
