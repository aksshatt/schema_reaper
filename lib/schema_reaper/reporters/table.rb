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
        @io.puts "  #{@a.paint("schema_reaper", :bold)}  " \
                 "#{@a.paint("#{@findings.size} finding#{"s" unless @findings.size == 1}", :bold)}  " \
                 "#{@a.paint("~#{Bytes.human(total_reclaimable)} reclaimable", :dim)}"
        @io.puts
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

        by_type = @findings.group_by(&:type).transform_values(&:size)
                           .sort_by { |_t, n| -n }
                           .map { |t, n| "#{t} #{n}" }.join(" · ")

        @io.puts "  #{tally}"
        @io.puts "  #{@a.paint(by_type, :dim)}"
      end

      def total_reclaimable
        @findings.sum(&:reclaimable_bytes)
      end
    end
  end
end
