# frozen_string_literal: true

require "json"
require "fileutils"
require "date"

module SchemaReaper
  # Persists known finding ids so CI only fails on *new* dead weight.
  #
  # Each accepted finding can carry a reason and an expiry date. Once an entry
  # expires, `scan --ci` treats the finding as new again, so "we'll deal with
  # it later" comes back around instead of living in the file forever.
  #
  # Reads the 2.0 format ({"ids": [...]}) as entries with no reason or expiry,
  # and keeps writing "ids" alongside "entries" so a 2.0.x gem sharing the
  # file (mixed versions across a team or CI) still sees the accepted set.
  #
  # scope: analyzer types (e.g. %w[dead_column]) a write or prune is limited
  # to -- what `--only` / `--except` selected. Entries of other analyzers
  # were not looked at in this run, so they are left exactly as they are.
  class Baseline
    Entry = Struct.new(:id, :reason, :expires_on, keyword_init: true) do
      def expired?(today = Date.today)
        !expires_on.nil? && expires_on < today
      end

      def type
        id.split("/").first
      end

      def to_h
        { "id" => id, "reason" => reason, "expires_on" => expires_on&.iso8601 }.compact
      end
    end

    def initialize(path)
      @path = path
    end

    def entries
      @entries ||= read_entries
    end

    # Ids still accepted today (expired entries excluded).
    def ids
      entries.reject(&:expired?).map(&:id)
    end

    def expired
      entries.select(&:expired?)
    end

    # Replaces the (in-scope part of the) baseline with exactly these
    # findings. A reason / expiry passed in applies to new entries and to
    # expired ones being re-accepted -- that is how an expired entry gets
    # renewed; unexpired entries keep what they had.
    def write(findings, reason: nil, expires_on: nil, scope: nil)
      known = entries.to_h { |e| [e.id, e] }
      kept = entries.reject { |e| in_scope?(e, scope) }
      written = findings.map(&:id).uniq.map do |id|
        entry = known[id]
        next Entry.new(id: id, reason: reason, expires_on: expires_on) unless entry
        next renew(entry, reason, expires_on) if entry.expired?

        entry
      end
      @entries = (kept + written).uniq(&:id).sort_by(&:id)
      save
    end

    # Drops entries for findings that no longer occur, without accepting any
    # new ones -- so a fixed finding can't hide a later regression with the
    # same id. @return [Array<String>] dropped ids
    def prune(findings, scope: nil)
      current = findings.map(&:id)
      dropped = entries.select { |e| in_scope?(e, scope) && !current.include?(e.id) }.map(&:id)
      @entries = entries.reject { |e| dropped.include?(e.id) }
      save
      dropped
    end

    # findings not present in the stored baseline (or whose entry expired)
    def new_among(findings)
      known = ids
      findings.reject { |f| known.include?(f.id) }
    end

    private

    def in_scope?(entry, scope)
      scope.nil? || scope.include?(entry.type)
    end

    def renew(entry, reason, expires_on)
      Entry.new(id: entry.id, reason: reason || entry.reason, expires_on: expires_on)
    end

    def save
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate(
                          "generated_at" => Time.now.utc.iso8601,
                          "ids" => ids.sort, # read by 2.0.x; unexpired only
                          "entries" => entries.map(&:to_h)
                        ))
    end

    def read_entries
      return [] unless File.exist?(@path)

      data = JSON.parse(File.read(@path))
      return data.fetch("ids", []).map { |id| Entry.new(id: id) } unless data.key?("entries")

      data["entries"].map do |e|
        Entry.new(id: e["id"], reason: e["reason"], expires_on: e["expires_on"] && Date.parse(e["expires_on"]))
      end
    rescue JSON::ParserError, ArgumentError
      []
    end
  end
end
