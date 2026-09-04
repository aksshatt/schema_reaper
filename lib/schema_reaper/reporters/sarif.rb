# frozen_string_literal: true

require "json"

module SchemaReaper
  module Reporters
    # SARIF 2.1.0 so findings show up in GitHub code scanning.
    class Sarif
      LEVEL = { high: "error", medium: "warning", low: "note" }.freeze

      def initialize(findings, io: $stdout)
        @findings = findings
        @io = io
      end

      def render
        @io.puts JSON.pretty_generate(document)
      end

      private

      def document
        {
          "$schema" => "https://json.schemastore.org/sarif-2.1.0.json",
          "version" => "2.1.0",
          "runs" => [{
            "tool" => { "driver" => {
              "name" => "schema_reaper",
              "version" => SchemaReaper::VERSION,
              "informationUri" => "https://github.com/akkshatt-shriffle/schema_reaper",
              "rules" => rules
            } },
            "results" => results
          }]
        }
      end

      def rules
        @findings.map(&:type).uniq.map do |type|
          { "id" => type.to_s, "name" => camelize(type.to_s),
            "shortDescription" => { "text" => "schema dead-weight: #{type}" } }
        end
      end

      def results
        @findings.map do |f|
          {
            "ruleId" => f.type.to_s,
            "level" => LEVEL.fetch(f.severity, "note"),
            "message" => { "text" => "#{f.id}: #{f.evidence.join("; ")}. Fix: #{f.suggested_fix}" },
            "properties" => {
              "confidence" => f.confidence,
              "reclaimableBytes" => f.reclaimable_bytes
            },
            "locations" => [{
              "physicalLocation" => {
                "artifactLocation" => { "uri" => "db/schema.rb" }
              }
            }]
          }
        end
      end

      def camelize(str) = str.split("_").map(&:capitalize).join
    end
  end
end
