# frozen_string_literal: true

require "json"
require "time"

module SchemaReaper
  module Reporters
    # Machine-readable output for CI and downstream tooling.
    class Json
      def initialize(findings, io: $stdout)
        @findings = findings
        @io = io
      end

      def render
        @io.puts JSON.pretty_generate(payload)
      end

      # Also used by History to snapshot a run.
      def payload
        {
          version: SchemaReaper::VERSION,
          generated_at: Time.now.utc.iso8601,
          count: @findings.size,
          reclaimable_bytes: @findings.sum(&:reclaimable_bytes),
          findings: @findings.map(&:to_h)
        }
      end
    end
  end
end
