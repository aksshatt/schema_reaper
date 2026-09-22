# frozen_string_literal: true

require_relative "bytes"
require_relative "console"

module SchemaReaper
  module Reporters
    # Formats History#trend into a readable progress block instead of a raw
    # hash dump.
    class Trend
      def initialize(data, io: $stdout, color: nil)
        @d = data
        @c = Console.new(out: io, color: color)
      end

      def render
        snaps = @d[:snapshots].to_i
        @c.title("trend", "#{snaps} snapshot#{"s" unless snaps == 1}")

        if snaps.zero?
          @c.info("no snapshots yet — run `schema_reaper trend` to record the first.")
          return
        end
        if snaps == 1
          @c.info("first snapshot recorded. Run this again later to see the delta.")
          dates
          return
        end

        counts
        bytes
        @c.blank
        @c.list("new since last run:", @d[:newly_introduced].to_a, colour: :yellow)
        @c.list("resolved since last run:", @d[:resolved_since_prev].to_a, colour: :green)
        @c.blank
        dates
      end

      private

      def counts
        total = signed(@d[:count_change_total])
        last = signed(@d[:count_change_last])
        @c.row("findings", @d.fetch(:latest_count, "—"),
               "#{total} since first run · #{last} since last")
      end

      def bytes
        delta = @d[:bytes_change_total].to_i
        sign = delta.negative? ? "-" : "+"
        @c.row("reclaimable", Bytes.human(@d.fetch(:latest_bytes, 0)),
               "#{sign}#{Bytes.human(delta.abs)} since first run")
      end

      def dates
        @c.row("first snapshot", short(@d[:first_at]))
        @c.row("latest", short(@d[:last_at]))
      end

      def signed(number)
        n = number.to_i
        n.positive? ? "+#{n}" : n.to_s
      end

      def short(iso)
        iso.to_s.split("T").first
      end
    end
  end
end
