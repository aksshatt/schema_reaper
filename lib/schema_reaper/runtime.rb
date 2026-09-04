# frozen_string_literal: true

require "json"
require "set"
require "fileutils"
require "time"

module SchemaReaper
  # Optional production signal: which columns are actually read/written at
  # runtime. Fused with the static scan to raise (or confirm) confidence.
  module Runtime
    # Aggregated view of a usage log, consumed by analyzers.
    Report = Struct.new(:accessed, :observed_days, keyword_init: true) do
      def self.empty
        new(accessed: Set.new, observed_days: 0)
      end

      def self.load(path)
        return empty unless path && File.exist?(path)

        seen = Set.new
        first = last = nil
        File.foreach(path) do |line|
          row = JSON.parse(line)
          seen << row["key"]
          ts = row["at"]
          first ||= ts
          last = ts
        rescue JSON::ParserError
          next
        end
        new(accessed: seen, observed_days: day_span(first, last))
      end

      def self.day_span(first, last)
        return 0 unless first && last

        ((Time.parse(last) - Time.parse(first)) / 86_400).ceil
      end

      def empty?
        accessed.empty?
      end

      def present?
        !empty?
      end

      def read?(table, column)
        accessed.include?("#{table}.#{column}")
      end
    end

    # Buffered writer for the usage log. Thread-safe append of JSON lines.
    class Store
      def initialize(path:, flush_every: 200)
        @path = path
        @flush_every = flush_every
        @buffer = []
        @mutex = Mutex.new
        FileUtils.mkdir_p(File.dirname(path))
      end

      def record(table, column)
        @mutex.synchronize do
          @buffer << %({"key":"#{table}.#{column}","at":"#{Time.now.utc.iso8601}"}\n)
          flush_locked if @buffer.size >= @flush_every
        end
      end

      def flush
        @mutex.synchronize { flush_locked }
      end

      private

      def flush_locked
        return if @buffer.empty?

        File.open(@path, "a") { |f| f.write(@buffer.join) }
        @buffer.clear
      end
    end

    # Patches ActiveRecord attribute access to feed a Store. Sampling keeps
    # production overhead negligible.
    module Tracker
      class << self
        attr_accessor :store, :sample_rate

        def install!(store:, sample_rate: 0.05)
          return if @installed

          self.store = store
          self.sample_rate = sample_rate
          require "active_record"
          ActiveRecord::Base.prepend(Hook)
          at_exit { store.flush }
          @installed = true
        end
      end

      module Hook
        def _read_attribute(name, *)
          SchemaReaper::Runtime::Tracker.note(self.class, name)
          super
        end
      end

      def self.note(klass, name)
        return unless store
        return unless rand < sample_rate
        return unless klass.respond_to?(:table_name) && klass.table_name

        store.record(klass.table_name, name.to_s)
      rescue StandardError
        nil
      end
    end
  end
end
