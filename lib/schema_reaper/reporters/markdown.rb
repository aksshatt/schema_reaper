# frozen_string_literal: true

require_relative "reclaim"

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

        @io.puts "\n#{summary_line}\n\n"
        @io.puts "| Severity | Confidence | Type | Target | Reclaims | Fix |"
        @io.puts "|---|---|---|---|---|---|"
        rows.each { |r| @io.puts r }
      end

      private

      # "54 finding(s). **~93.8 KB reclaimable.**" -- or, when the row count is
      # unknown or the estimate is genuinely zero, no reclaim clause at all,
      # matching the terminal report rather than claiming a number it does not
      # have.
      def summary_line
        text = Reclaim.summary(@findings)
        line = "#{@findings.size} finding(s)."
        line + (text ? " **#{text}.**" : "")
      end

      def rows
        @findings.sort_by { |f| -f.confidence }.map do |f|
          target = [f.table, f.column, f.index].compact.join("`.`")
          "| #{f.severity} | #{(f.confidence * 100).round}% | `#{f.type}` | " \
            "`#{target}` | #{Reclaim.cell(f)} | #{f.suggested_fix} |"
        end
      end
    end
  end
end
