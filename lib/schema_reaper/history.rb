# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module SchemaReaper
  # Append-only log of scan snapshots, so cleanup progress is visible over time.
  class History
    Snapshot = Struct.new(:at, :count, :reclaimable_bytes, :ids, keyword_init: true)

    def initialize(path = ".schema_reaper/history.jsonl")
      @path = path
    end

    def record(findings)
      FileUtils.mkdir_p(File.dirname(@path))
      row = {
        "at" => Time.now.utc.iso8601,
        "count" => findings.size,
        "reclaimable_bytes" => findings.sum(&:reclaimable_bytes),
        "ids" => findings.map(&:id).sort
      }
      File.open(@path, "a") { |f| f.puts JSON.generate(row) }
      row
    end

    def snapshots
      return [] unless File.exist?(@path)

      File.foreach(@path).filter_map do |line|
        r = JSON.parse(line)
        Snapshot.new(at: r["at"], count: r["count"],
                     reclaimable_bytes: r["reclaimable_bytes"], ids: r["ids"])
      rescue JSON::ParserError
        nil
      end
    end

    # @return [Hash] delta between the first and last snapshot plus current-vs-previous
    def trend
      snaps = snapshots
      return { snapshots: 0 } if snaps.empty?

      first = snaps.first
      last = snaps.last
      prev = snaps[-2] || first
      {
        snapshots: snaps.size,
        first_at: first.at,
        last_at: last.at,
        count_change_total: last.count - first.count,
        count_change_last: last.count - prev.count,
        newly_introduced: (last.ids - prev.ids),
        resolved_since_prev: (prev.ids - last.ids),
        bytes_change_total: last.reclaimable_bytes - first.reclaimable_bytes
      }
    end
  end
end
