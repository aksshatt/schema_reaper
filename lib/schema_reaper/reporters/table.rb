# frozen_string_literal: true

require_relative "bytes"

module SchemaReaper
  module Reporters
    # Human-readable terminal output, sorted by confidence then severity.
    class Table
      SEV_ORDER = { high: 0, medium: 1, low: 2 }.freeze

      def initialize(findings, io: $stdout)
        @findings = findings
        @io = io
      end

      def render
        if @findings.empty?
          @io.puts "schema_reaper: no findings. Schema is lean."
          return
        end

        sorted.each { |f| render_finding(f) }
        @io.puts
        @io.puts "#{@findings.size} finding(s). " \
                 "~#{Bytes.human(total_reclaimable)} reclaimable."
      end

      private

      def render_finding(f)
        target = [f.table, f.column, f.index].compact.join(".")
        @io.puts format("[%-6s %3d%%] %-14s %s",
                        f.severity, (f.confidence * 100).round, f.type, target)
        f.evidence.each { |e| @io.puts "        - #{e}" }
        @io.puts "        fix: #{f.suggested_fix}"
      end

      def sorted
        @findings.sort_by { |f| [-f.confidence, SEV_ORDER.fetch(f.severity, 9)] }
      end

      def total_reclaimable
        @findings.sum(&:reclaimable_bytes)
      end
    end
  end
end
