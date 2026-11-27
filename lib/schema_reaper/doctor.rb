# frozen_string_literal: true

require "time"

module SchemaReaper
  # `schema_reaper doctor`: checks everything a scan's accuracy depends on and
  # says what to fix, so a quiet report can be trusted to mean "nothing dead"
  # rather than "nothing measured".
  class Doctor
    Check = Struct.new(:status, :label, :detail, keyword_init: true) # status: :ok | :warn | :fail

    STATS_FRESH_DAYS = 7
    ICON = { ok: "✓", warn: "!", fail: "✗" }.freeze

    def initialize(config:, root: Dir.pwd, introspector: nil, console: Reporters::Console.new)
      @config = config
      @root = root
      @introspector = introspector
      @console = console
      @checks = []
    end

    # @return [Boolean] true unless a check failed outright
    def call
      check_scan_paths
      check_database
      check_runtime_log
      check_baseline
      check_schema_file
      check_alerts
      render
      @checks.none? { |c| c.status == :fail }
    end

    private

    def ok(label, detail = nil)
      @checks << Check.new(status: :ok, label: label, detail: detail)
    end

    def warn_check(label, detail)
      @checks << Check.new(status: :warn, label: label, detail: detail)
    end

    def fail_check(label, detail)
      @checks << Check.new(status: :fail, label: label, detail: detail)
    end

    def check_scan_paths
      missing = @config.scan_paths.reject { |p| Dir.exist?(File.join(@root, p)) }
      return ok("scan paths", @config.scan_paths.join(", ")) if missing.empty?

      warn_check("scan paths", "not found: #{missing.join(", ")} -- code there can't mark anything as used")
    end

    def check_database
      intro = @introspector || Introspect::Postgres.new(@config.database_url, schemas: @config.schemas)
      diag = intro.diagnostics
      ok("database", "connected, PostgreSQL #{diag[:server_version]}")
      check_stats_reset(diag[:stats_reset])
      check_analyze(diag[:never_analyzed])
      check_query_history(intro.call)
      if diag[:in_recovery]
        warn_check("replica", "this is a read replica -- index usage here doesn't cover the primary")
      end
    rescue Error => e
      fail_check("database", e.message)
    end

    def check_stats_reset(reset_at)
      return ok("statistics", "never reset") if reset_at.nil?

      days = ((Time.now - Time.parse(reset_at.to_s)) / 86_400).floor
      return ok("statistics", "collected for #{days} day(s)") if days >= STATS_FRESH_DAYS

      warn_check("statistics", "reset #{days} day(s) ago -- unused_index needs a longer window to be trusted")
    end

    def check_analyze(tables)
      return ok("ANALYZE", "every table has planner statistics") if tables.empty?

      sample = tables.first(5).join(", ") + (tables.size > 5 ? ", ..." : "")
      warn_check("ANALYZE", "#{tables.size} table(s) never analysed (#{sample}) -- " \
                            "row counts and null/distinct checks are blind there; run ANALYZE")
    end

    def check_query_history(schema)
      return ok("query history", "#{schema.index_scan_total} index scans recorded") if schema.query_history?

      warn_check("query history", "only #{schema.index_scan_total} index scan(s) -- unused_index will sit out; " \
                                  "scan a database that serves real traffic")
    end

    def check_runtime_log
      report = Runtime::Report.load(@config.runtime_log)
      need = @config.min_age_days || Config::DEFAULTS["min_age_days"]
      if report.empty?
        warn_check("runtime log", "none at #{@config.runtime_log} -- dead_column confidence stays capped at " \
                                  "#{Analyzers::DeadColumn::STATIC_ONLY_CAP}; see README > Runtime signal")
      elsif report.observed_days < need
        warn_check("runtime log", "#{report.observed_days} of #{need} day(s) observed -- not trusted yet")
      else
        ok("runtime log", "#{report.observed_days} day(s), #{report.accessed.size} column(s) seen")
      end
    end

    def check_baseline
      base = Baseline.new(@config.baseline_path)
      return ok("baseline", "none (scan --ci would fail on every finding)") if base.entries.empty?

      expired = base.expired
      return ok("baseline", "#{base.entries.size} accepted finding(s)") if expired.empty?

      warn_check("baseline", "#{expired.size} entr#{expired.size == 1 ? "y has" : "ies have"} expired: " \
                             "#{expired.map(&:id).first(3).join(", ")}")
    end

    def check_schema_file
      path = SchemaLocator::CANDIDATES.find { |p| File.exist?(File.join(@root, p)) }
      return ok("schema file", path) if path

      warn_check("schema file", "no db/schema.rb or db/structure.sql -- SARIF results can't point at a line")
    end

    # Only meaningful inside a Rails app with the install generator's
    # initializer loaded.
    def check_alerts
      return unless defined?(AlertConfig) && defined?(Rails)

      cfg = AlertConfig.instance
      unless cfg.configured?
        return warn_check("alerts", "no emails or webhook_url configured -- scheduled scans report nowhere")
      end

      channels = [("email (#{cfg.emails.size})" if cfg.emails?), ("webhook" if cfg.webhook?)].compact
      ok("alerts", "#{channels.join(" + ")}, alert_on: #{cfg.alert_on}")
    end

    def render
      @console.title("doctor")
      @checks.each do |c|
        line = format("%<icon>s %<label>-14s %<detail>s", icon: ICON[c.status], label: c.label, detail: c.detail)
        @console.info(line)
      end
      @console.blank
      counts = @checks.group_by(&:status).transform_values(&:size)
      @console.info("#{counts.fetch(:ok, 0)} ok, #{counts.fetch(:warn, 0)} warning(s), " \
                    "#{counts.fetch(:fail, 0)} failed")
    end
  end
end
