# frozen_string_literal: true

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

        sorted.each do |f|
          @io.puts format("[%-6s %s%%] %-24s %-24s %s",
                          f.severity, (f.confidence * 100).round,
                          f.table, f.column.to_s, f.type)
          f.evidence.each { |e| @io.puts "        - #{e}" }
          @io.puts "        fix: #{f.suggested_fix}"
        end
        @io.puts
        @io.puts "#{@findings.size} finding(s). ~#{total_bytes} bytes/row reclaimable."
      end

      private

      def sorted
        @findings.sort_by { |f| [-f.confidence, SEV_ORDER.fetch(f.severity, 9)] }
      end

      def total_bytes
        @findings.sum { |f| f.bytes_per_row.to_i }
      end
    end
  end
end
