# frozen_string_literal: true

module SchemaReaper
  # Runs a scan and delivers the report through whatever channels AlertConfig
  # has configured. Enqueued two ways: on the schedule an app generates via
  # `rails generate schema_reaper:install` (whenever/sidekiq-cron), and
  # on-demand by the generated manual-trigger controller -- same job either
  # way, so there is exactly one code path to keep correct.
  class ScanJob < ActiveJob::Base
    queue_as :default

    # Rails' :async adapter (the default until Rails 8 unless an app sets up
    # a real backend) runs jobs on a thread pool inside the enqueueing
    # process. Fine in a web server; fatal in a one-shot `rake` process,
    # which exits the moment the task returns and takes the queued job with
    # it -- the scheduled scan would silently never run.
    def self.in_process_queue?
      queue_adapter.instance_of?(::ActiveJob::QueueAdapters::AsyncAdapter)
    end

    # What the scheduled cron entry (`rake schema_reaper:alert`) calls:
    # enqueue normally, but on an in-process queue run inline instead --
    # email included -- so the scan isn't lost when the process exits.
    def self.run_scheduled
      return perform_later unless in_process_queue?

      puts "[schema_reaper] ActiveJob adapter is :async -- running the scan inline"
      perform_now(deliver_mail_now: true)
    end

    # `deliver_mail_now:` is for running inline from a process about to exit
    # (see the schema_reaper:alert rake task) -- a deliver_later there would
    # be lost for the same reason as above.
    def perform(deliver_mail_now: false)
      findings = Runner.new.run
      Notifier.new(findings, mail_delivery: deliver_mail_now ? :now : :later).deliver
    end
  end
end
