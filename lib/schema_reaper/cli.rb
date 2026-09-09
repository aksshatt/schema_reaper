# frozen_string_literal: true

require "thor"
require_relative "../schema_reaper"

module SchemaReaper
  # Command-line entry point. See `exe/schema_reaper`.
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    class_option :config, type: :string, default: ".schema_reaper.yml",
                          desc: "path to config file"

    desc "scan", "Scan schema + code and report dead weight"
    option :format, type: :string, default: "table",
                    enum: %w[table json markdown sarif]
    option :ci, type: :boolean, default: false,
                desc: "exit non-zero on findings not in the baseline"
    option :record, type: :boolean, default: false,
                    desc: "append this run to the history log"
    option :min_confidence, type: :numeric, default: 0.0
    option :color, type: :boolean, default: nil,
                   desc: "force colour on/off for the table report (default: auto)"
    def scan
      findings = run.select { |f| f.confidence >= options[:min_confidence] }
      render_report(findings)

      History.new(config.history_log).record(findings) if options[:record]
      enforce_baseline(findings) if options[:ci]
    end

    desc "baseline", "Write current findings to the baseline file"
    def baseline
      findings = run
      Baseline.new(config.baseline_path).write(findings)
      console.title("baseline")
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

    desc "generate-migration TABLE COLUMN", "Emit a staged removal migration pair"
    def generate_migration(table, column)
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

    desc "version", "Print version"
    def version
      say(SchemaReaper::VERSION)
    end

    private

    def config
      @config ||= Config.load(options[:config])
    end

    def run
      Runner.new(config: config).run
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
      new_ones = Baseline.new(config.baseline_path).new_among(findings)
      return if new_ones.empty?

      console.problem(
        "#{new_ones.size} new finding#{"s" unless new_ones.size == 1} since the baseline",
        items: new_ones.map(&:id)
      )
      exit 1
    end
  end
end
