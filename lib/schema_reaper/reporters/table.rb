# frozen_string_literal: true

require_relative "bytes"
require_relative "ansi"
require_relative "rollup"
require_relative "reclaim"

module SchemaReaper
  module Reporters
    # Human-readable terminal report: a summary line, then findings. Findings
    # that say the same thing about different tables are rolled up into one
    # entry; the rest are grouped by table and sorted by confidence. Colour is
    # used only on an interactive terminal (see Ansi).
    class Table
      SEV_ORDER = { high: 0, medium: 1, low: 2 }.freeze

      # Width to wrap the target list of a rolled-up entry.
      TARGET_LINE_WIDTH = 92

      def initialize(findings, io: $stdout, color: nil)
        @findings = findings
        @io = io
        @a = Ansi.new(io: io, enabled: color)
      end

      def render
        return render_clean if @findings.empty?

        header
        rolled_up.each { |key, group| render_rollup(key, group) }
        grouped(itemised).each { |table, group| render_table(table, group) }
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

      def reclaim_text
        Reclaim.summary(@findings)
      end

      def rolled_up
        partitioned.first
      end

      def itemised
        partitioned.last
      end

      def partitioned
        @partitioned ||= Rollup.partition(@findings)
      end

      def render_rollup(key, group)
        type, evidence, fix = key
        first = group.first
        @io.puts rollup_head(type, first, group.size)
        @io.puts "           #{@a.paint(evidence, :dim)}"
        @io.puts "           #{@a.paint("→ #{fix}", :green)}"
        target_lines(group).each { |line| @io.puts "           #{@a.paint(line, :dim)}" }
        @io.puts
      end

      def rollup_head(type, first, count)
        pct = (first.confidence * 100).round
        bar = @a.confidence_bar(first.confidence, first.severity)
        sev = @a.severity(first.severity, format("%-6s", first.severity))
        format("    %s %3d%%  %s  %s  %s", bar, pct, sev,
               @a.paint(format("%-19s", type), :bold),
               @a.paint("#{count} targets", :bold, :magenta))
      end

      # "users.team_id · orders.buyer_id · ..." wrapped to a readable width.
      def target_lines(group)
        labels = group.map { |f| [f.table, f.target_label].compact.join(".") }.sort
        labels.each_with_object([+""]) do |label, lines|
          lines << +"" if !lines.last.empty? && lines.last.length + label.length + 3 > TARGET_LINE_WIDTH
          lines.last << " · " unless lines.last.empty?
          lines.last << label
        end
      end

      def grouped(findings)
        findings
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
