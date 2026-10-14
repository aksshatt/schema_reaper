# frozen_string_literal: true

module SchemaReaper
  module Reporters
    # Slack Block Kit payload for the scheduled report. Slack renders neither
    # Markdown tables nor messages past ~40k characters, so this is a summary
    # with the most important findings, not the whole report.
    class Slack
      MAX_LISTED = 10
      SEVERITY_ICON = { high: ":red_circle:", medium: ":large_orange_circle:", low: ":white_circle:" }.freeze

      # changes - {new: [Finding], resolved: [String id]} or nil on a first report
      def initialize(findings, changes: nil)
        @findings = findings
        @changes = changes
      end

      def payload
        { "text" => summary, "blocks" => blocks }
      end

      # Also the notification text, and what a client without Block Kit shows.
      def summary
        line = "schema_reaper: #{@findings.size} finding#{"s" unless @findings.size == 1}"
        return line unless @changes

        "#{line} (#{@changes[:new].size} new, #{@changes[:resolved].size} resolved since the last report)"
      end

      private

      def blocks
        out = [{ "type" => "section", "text" => mrkdwn("*#{summary}*") }]
        listed = @changes ? @changes[:new] : @findings
        out << list_block(@changes ? "New" : "Top findings", listed) if listed.any?
        out << resolved_block if @changes && @changes[:resolved].any?
        out << { "type" => "context",
                 "elements" => [mrkdwn("Full report: `bundle exec schema_reaper scan`")] }
        out
      end

      def list_block(title, findings)
        lines = findings.first(MAX_LISTED).map do |f|
          "#{SEVERITY_ICON.fetch(f.severity, "")} `#{f.id}` -- #{f.suggested_fix}"
        end
        lines << "_...and #{findings.size - MAX_LISTED} more_" if findings.size > MAX_LISTED
        { "type" => "section", "text" => mrkdwn(truncate("*#{title}*\n#{lines.join("\n")}")) }
      end

      def resolved_block
        ids = @changes[:resolved]
        text = "*Resolved*\n#{ids.first(MAX_LISTED).map { |id| "~#{id}~" }.join("\n")}"
        text += "\n_...and #{ids.size - MAX_LISTED} more_" if ids.size > MAX_LISTED
        { "type" => "section", "text" => mrkdwn(truncate(text)) }
      end

      # A section's text is capped at 3000 characters by Slack.
      def truncate(text)
        text.length > 3000 ? "#{text[0, 2990]}..." : text
      end

      def mrkdwn(text)
        { "type" => "mrkdwn", "text" => text }
      end
    end
  end
end
