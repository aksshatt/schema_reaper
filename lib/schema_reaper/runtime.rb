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

      # Reads the rotated generation (path.1) too, so rotation never shortens
      # the observed window. Several processes append to one log, so lines are
      # not in time order -- the span is min..max, not first..last line.
      def self.load(path)
        return empty unless path

        files = [Store.rotated_path(path), path].select { |f| File.exist?(f) }
        return empty if files.empty?

        seen = Set.new
        first = last = nil
        files.each do |file|
          File.foreach(file) do |line|
            row = JSON.parse(line)
            seen << row["key"]
            # Store writes UTC ISO8601 ("2026-01-05T00:00:00Z"), which sorts
            # correctly as a string -- far cheaper than parsing every line of
            # a log that can hold millions. Only the extremes are parsed.
            ts = row["at"]
            next unless ts.is_a?(String)

            first = ts if first.nil? || ts < first
            last = ts if last.nil? || ts > last
          rescue JSON::ParserError
            next
          end
        end
        new(accessed: seen, observed_days: day_span(first, last))
      end

      def self.day_span(first, last)
        return 0 unless first && last

        ((Time.parse(last) - Time.parse(first)) / 86_400).ceil
      rescue ArgumentError
        0
      end

      # Raw-SQL access recorded by the tracker's SQL subscriber, keyed
      # "table.*": the table was touched, but by no column we can name.
      def table_accessed?(table)
        accessed.any? { |k| k.start_with?("#{table}.") }
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
    #
    # Past max_bytes the log is renamed to `<path>.1` (replacing any older
    # generation) and a fresh one started, so disk use stays under roughly
    # 2 x max_bytes. nil disables rotation.
    class Store
      def self.rotated_path(path)
        "#{path}.1"
      end

      def initialize(path:, flush_every: 200, max_bytes: Config::DEFAULTS["runtime_log_max_bytes"])
        @path = path
        @flush_every = flush_every
        @max_bytes = max_bytes
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
        rotate_if_needed
      end

      # Several processes (Puma workers) share one log, so the size check and
      # the rename happen under an exclusive flock and the size is checked
      # again once it's held: otherwise two workers that both saw an
      # oversized log would rotate twice, and the second rename would put a
      # nearly empty log over the full generation in <path>.1.
      def rotate_if_needed
        return unless @max_bytes && File.size?(@path).to_i > @max_bytes

        File.open("#{@path}.lock", File::RDWR | File::CREAT, 0o644) do |lock|
          lock.flock(File::LOCK_EX)
          File.rename(@path, self.class.rotated_path(@path)) if File.size?(@path).to_i > @max_bytes
        end
      rescue SystemCallError
        nil
      end
    end

    # Patches ActiveRecord attribute access to feed a Store. Sampling keeps
    # production overhead negligible.
    module Tracker
      class << self
        attr_accessor :store, :sample_rate

        # track_sql: also sample the tables named in every executed SQL
        # statement, so a table read only through find_by_sql, a raw
        # connection.execute or a view-backed report still counts as used.
        def install!(store:, sample_rate: 0.05, track_sql: true)
          return if @installed

          self.store = store
          self.sample_rate = sample_rate
          require "active_record"
          ActiveRecord::Base.prepend(Hook)
          subscribe_sql if track_sql
          at_exit { store.flush }
          @installed = true
        end

        private

        def subscribe_sql
          ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
            Tracker.note_sql(payload[:sql], payload[:name])
          end
        end
      end

      # The relation after FROM / JOIN / UPDATE / INTO, optionally
      # schema-qualified and double-quoted: "billing"."invoices" -> billing.invoices.
      #
      # INSERT INTO targets are left out on purpose: a table that is only ever
      # written (an audit log nobody reads) is exactly what dead_table should
      # be able to find. INSERT ... SELECT still records its FROM tables.
      SQL_TABLE_RE = /\b(?:FROM|JOIN|UPDATE)\s+((?:"?\w+"?\.)?"?\w+"?)/i.freeze
      SKIP_SQL_NAMES = %w[SCHEMA TRANSACTION].freeze

      def self.note_sql(sql, name = nil)
        return unless store && sql
        return if SKIP_SQL_NAMES.include?(name)
        return unless rand < sample_rate

        # "public"."users" is the same table the app (and the schema) calls users
        sql.scan(SQL_TABLE_RE).flatten.map { |t| t.delete('"').delete_prefix("public.") }.uniq.each do |table|
          next if table.start_with?("pg_", "information_schema")

          store.record(table, "*")
        end
      rescue StandardError
        nil
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
