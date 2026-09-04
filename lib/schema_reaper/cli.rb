# frozen_string_literal: true

require "thor"
require_relative "../schema_reaper"

module SchemaReaper
  # Command-line entry point. See `exe/schema_reaper`.
  class CLI < Thor
    def self.exit_on_failure? = true

    class_option :config, type: :string, default: ".schema_reaper.yml",
                          desc: "path to config file"

    desc "scan", "Scan schema + code and report dead weight"
    option :format, type: :string, default: "table", enum: %w[table json]
    option :ci, type: :boolean, default: false,
                desc: "exit non-zero on findings not in the baseline"
    def scan
      findings = build_runner.run
      reporter_for(options[:format]).new(findings).render

      return unless options[:ci]

      new_ones = Baseline.new(config.baseline_path).new_among(findings)
      return unless new_ones.any?

      warn "schema_reaper: #{new_ones.size} new finding(s) since baseline"
      exit 1
    end

    desc "baseline", "Write current findings to the baseline file"
    def baseline
      findings = build_runner.run
      Baseline.new(config.baseline_path).write(findings)
      say "wrote #{findings.size} finding(s) to #{config.baseline_path}"
    end

    desc "generate-migration TABLE COLUMN", "Emit a staged removal migration pair"
    def generate_migration(table, column)
      paths = MigrationGenerator.new(table: table, column: column).call
      paths.each { |p| say "created #{p}" }
    end

    desc "version", "Print version"
    def version = say(SchemaReaper::VERSION)

    private

    def config = @config ||= Config.load(options[:config])

    def build_runner = Runner.new(config: config)

    def reporter_for(fmt)
      fmt == "json" ? Reporters::Json : Reporters::Table
    end
  end
end
