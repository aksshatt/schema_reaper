# frozen_string_literal: true

require "json"

module SchemaReaper
  module Reporters
    # Machine-readable output for CI and downstream tooling.
    class Json
      def initialize(findings, io: $stdout)
        @findings = findings
        @io = io
      end

      def render
        @io.puts JSON.pretty_generate(
          version: SchemaReaper::VERSION,
          generated_at: Time.now.utc.iso8601,
          count: @findings.size,
          findings: @findings.map(&:to_h)
        )
      end
    end
  end
end
