# frozen_string_literal: true

require_relative "bytes"

module SchemaReaper
  module Reporters
    # GitHub-flavoured Markdown, suitable for a PR comment or job summary.
    class Markdown
      def initialize(findings, io: $stdout)
        @findings = findings
        @io = io
      end

      def render
        @io.puts "## schema_reaper"
        if @findings.empty?
          @io.puts "\nNo findings. Schema is lean. :sparkles:"
          return
        end

        @io.puts "\n#{@findings.size} finding(s), " \
                 "~**#{Bytes.human(total)}** reclaimable.\n\n"
        @io.puts "| Severity | Confidence | Type | Target | Reclaims | Fix |"
        @io.puts "|---|---|---|---|---|---|"
        rows.each { |r| @io.puts r }
      end

      private

      def rows
        @findings.sort_by { |f| -f.confidence }.map do |f|
          target = [f.table, f.column, f.index].compact.join("`.`")
          "| #{f.severity} | #{(f.confidence * 100).round}% | `#{f.type}` | " \
            "`#{target}` | #{Bytes.human(f.reclaimable_bytes)} | #{f.suggested_fix} |"
        end
      end

      def total
        @findings.sum(&:reclaimable_bytes)
      end
    end
  end
end
