# frozen_string_literal: true

require "rails/railtie"

module SchemaReaper
  # Loads rake tasks and, when enabled, installs the runtime tracker.
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks/schema_reaper.rake", __dir__)
    end

    initializer "schema_reaper.runtime_tracker" do
      next unless ENV["SCHEMA_REAPER_TRACK"] == "1"

      config = SchemaReaper::Config.load
      store = SchemaReaper::Runtime::Store.new(path: config.runtime_log)
      rate = (ENV["SCHEMA_REAPER_SAMPLE"] || "0.05").to_f
      SchemaReaper::Runtime::Tracker.install!(store: store, sample_rate: rate)
    end
  end
end
