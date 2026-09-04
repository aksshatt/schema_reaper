# frozen_string_literal: true

require "json"
require "fileutils"

module SchemaReaper
  # Persists known finding ids so CI only fails on *new* dead weight.
  class Baseline
    def initialize(path)
      @path = path
    end

    def ids
      return [] unless File.exist?(@path)

      JSON.parse(File.read(@path)).fetch("ids", [])
    rescue JSON::ParserError
      []
    end

    def write(findings)
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate(
                          "generated_at" => Time.now.utc.iso8601,
                          "ids" => findings.map(&:id).sort
                        ))
    end

    # findings not present in the stored baseline
    def new_among(findings)
      known = ids
      findings.reject { |f| known.include?(f.id) }
    end
  end
end
