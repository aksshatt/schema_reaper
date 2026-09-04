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
    def scan
      findings = run.select { |f| f.confidence >= options[:min_confidence] }
      SchemaReaper.reporter(options[:format]).new(findings).render

      History.new(config.history_log).record(findings) if options[:record]
      enforce_baseline(findings) if options[:ci]
    end

    desc "baseline", "Write current findings to the baseline file"
    def baseline
      findings = run
      Baseline.new(config.baseline_path).write(findings)
      say "wrote #{findings.size} finding(s) to #{config.baseline_path}"
    end

    desc "trend", "Append a snapshot and print progress over time"
    def trend
      History.new(config.history_log).record(run)
      require "pp"
      pp History.new(config.history_log).trend
    end

    desc "generate-migration TABLE COLUMN", "Emit a staged removal migration pair"
    def generate_migration(table, column)
      MigrationGenerator.new(table: table, column: column).call
                        .each { |p| say "created #{p}" }
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
    end

    def enforce_baseline(findings)
      new_ones = Baseline.new(config.baseline_path).new_among(findings)
      return if new_ones.empty?

      warn "schema_reaper: #{new_ones.size} new finding(s) since baseline"
      new_ones.each { |f| warn "  - #{f.id}" }
      exit 1
    end
  end
end
