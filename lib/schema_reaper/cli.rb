# frozen_string_literal: true

require "thor"
require_relative "../schema_reaper"
require_relative "cli/baseline_support"

module SchemaReaper
  # Command-line entry point. See `exe/schema_reaper`.
  class CLI < Thor
    include BaselineSupport

    def self.exit_on_failure?
      true
    end

    class_option :config, type: :string, default: ".schema_reaper.yml",
                          desc: "path to config file"
    class_option :color, type: :boolean, default: nil,
                         desc: "force colour on/off (default: auto)"
    class_option :only, type: :array, desc: "run only these analyzers (e.g. dead_column unused_index)"
    class_option :except, type: :array, desc: "skip these analyzers"

    desc "scan", "Scan schema + code and report dead weight"
    option :format, type: :string, default: "table",
                    enum: %w[table json markdown sarif]
    option :ci, type: :boolean, default: false,
                desc: "exit non-zero on findings not in the baseline"
    option :record, type: :boolean, default: false,
                    desc: "append this run to the history log"
    option :min_confidence, type: :numeric,
                            desc: "hide findings below this confidence (default: min_confidence in config, 0.0)"
    def scan
      findings = run(min_confidence: options[:min_confidence])
      render_report(findings)

      History.new(config.history_log).record(findings) if options[:record]
      enforce_baseline(findings) if options[:ci]
    end

    desc "baseline", "Write current findings to the baseline file"
    option :reason, type: :string, desc: "why these findings are accepted (stored on newly added entries)"
    option :expires, type: :string, desc: "YYYY-MM-DD after which `scan --ci` fails on them again"
    option :prune, type: :boolean, default: false,
                   desc: "only drop entries for findings that no longer occur; accept nothing new"
    def baseline
      findings = run
      store = Baseline.new(config.baseline_path)
      console.title("baseline")
      return report_pruned(store.prune(findings)) if options[:prune]

      store.write(findings, reason: options[:reason], expires_on: parse_date(options[:expires]))
      console.ok("recorded #{findings.size} finding#{"s" unless findings.size == 1} " \
                 "as the accepted baseline")
      console.info("file: #{config.baseline_path}")
      console.info("`scan --ci` now fails only on findings that appear after this point.")
    end

    desc "trend", "Append a snapshot and print progress over time"
    def trend
      history = History.new(config.history_log)
      history.record(run)
      Reporters::Trend.new(history.trend, color: options[:color]).render
    end

    desc "generate-migration TABLE [COLUMN]",
         "Emit a staged removal migration pair for a column, or a removal migration for an index (--index) or table"
    option :index, type: :string, desc: "name of an index on TABLE to remove instead of a column"
    def generate_migration(table, column = nil)
      if options[:index] && column
        console.problem("pass either COLUMN or --index, not both")
        exit 1
      end
      return generate_index_migration(table, options[:index]) if options[:index]
      return generate_table_migration(table) unless column

      paths = MigrationGenerator.new(table: table, column: column).call
      console.title("generate-migration", "#{table}.#{column}")
      console.ok("created two migrations:")
      paths.each { |p| console.info("  #{p}") }
      console.blank
      console.list("next:", [
                     "deploy step 1 (adds `#{column}` to ignored_columns) and let it soak",
                     "run step 2 (`remove_column`) only once nothing has broken"
                   ])
    end

    desc "explain ID", "Show everything known about one finding and the command to act on it"
    def explain(id)
      exit 1 unless Explain.new(run, config: config, console: console).call(id)
    end

    desc "doctor", "Check the database, statistics, runtime log, baseline and alert setup"
    def doctor
      exit 1 unless Doctor.new(config: config, console: console).call
    end

    desc "version", "Print version"
    def version
      say(SchemaReaper::VERSION)
    end

    private

    def generate_index_migration(table, index)
      path = MigrationGenerator.new(table: table, index: index).call.first
      console.title("generate-migration", "#{table} · #{index}")
      console.ok("created #{path}")
      console.info("runs with algorithm: :concurrently, so it does not lock writes to #{table}")
    end

    def generate_table_migration(table)
      path = MigrationGenerator.new(table: table).call.first
      console.title("generate-migration", table)
      console.ok("created #{path}")
      console.list("before running it:", [
                     "confirm no external consumer (reports, ETL, other services) reads #{table}",
                     "take a backup -- its `down` cannot bring the data back"
                   ])
    end

    def config
      @config ||= Config.load(options[:config])
    end

    def run(min_confidence: nil)
      Runner.new(config: config, only: options[:only], except: options[:except],
                 min_confidence: min_confidence).run
    rescue SchemaReaper::Error => e
      console.problem(e.message)
      exit 1
    end

    def render_report(findings)
      if options[:format] == "table"
        Reporters::Table.new(findings, color: options[:color]).render
      else
        SchemaReaper.reporter(options[:format]).new(findings).render
      end
    end

    def console
      @console ||= Reporters::Console.new(color: options[:color])
    end

    def enforce_baseline(findings)
      store = Baseline.new(config.baseline_path)
      warn_expired(store.expired, findings)
      new_ones = store.new_among(findings)
      return if new_ones.empty?

      console.problem(
        "#{new_ones.size} new finding#{"s" unless new_ones.size == 1} since the baseline",
        items: new_ones.map(&:id)
      )
      exit 1
    end
  end
end
