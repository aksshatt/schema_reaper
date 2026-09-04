# frozen_string_literal: true

require "schema_reaper"

namespace :schema_reaper do
  desc "Scan schema + code for dead weight (FORMAT=table|json|markdown|sarif)"
  task scan: :environment do
    findings = SchemaReaper::Runner.new.run
    SchemaReaper.reporter(ENV.fetch("FORMAT", "table")).new(findings).render
  end

  desc "Record current findings to the baseline file"
  task baseline: :environment do
    findings = SchemaReaper::Runner.new.run
    SchemaReaper::Baseline.new(SchemaReaper::Config.load.baseline_path).write(findings)
  end

  desc "Append a snapshot to the history log and print the trend"
  task trend: :environment do
    config = SchemaReaper::Config.load
    findings = SchemaReaper::Runner.new(config: config).run
    history = SchemaReaper::History.new(config.history_log)
    history.record(findings)
    pp history.trend
  end
end
