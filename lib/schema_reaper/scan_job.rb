# frozen_string_literal: true

module SchemaReaper
  # Runs a scan and delivers the report through whatever channels AlertConfig
  # has configured. Enqueued two ways: on the schedule an app generates via
  # `rails generate schema_reaper:install` (whenever/sidekiq-cron), and
  # on-demand by the generated manual-trigger controller -- same job either
  # way, so there is exactly one code path to keep correct.
  class ScanJob < ActiveJob::Base
    queue_as :default

    def perform
      findings = Runner.new.run
      Notifier.new(findings).deliver
    end
  end
end
