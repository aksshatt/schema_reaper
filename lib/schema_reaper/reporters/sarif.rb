# frozen_string_literal: true

require "json"

module SchemaReaper
  module Reporters
    # SARIF 2.1.0 so findings show up in GitHub code scanning.
    class Sarif
      LEVEL = { high: "error", medium: "warning", low: "note" }.freeze

      def initialize(findings, io: $stdout, locator: SchemaLocator.new)
        @findings = findings
        @io = io
        @locator = locator
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
              "informationUri" => "https://github.com/aksshatt/schema_reaper",
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
            "locations" => locations_for(f)
          }
        end
      end

      # GitHub code scanning requires a location on every result, so with no
      # schema file in the repo fall back to the conventional path, unlined.
      def locations_for(finding)
        loc = @locator.locate(finding)
        return [{ "physicalLocation" => { "artifactLocation" => { "uri" => "db/schema.rb" } } }] unless loc

        [{ "physicalLocation" => {
          "artifactLocation" => { "uri" => loc.path },
          "region" => { "startLine" => loc.line }
        } }]
      end

      def camelize(str)
        str.split("_").map(&:capitalize).join
      end
    end
  end
end
