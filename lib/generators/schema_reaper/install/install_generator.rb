# frozen_string_literal: true

require "rails/generators"
require "securerandom"

module SchemaReaper
  module Generators
    # `rails generate schema_reaper:install` -- one-time setup for unattended
    # production scanning: an initializer for where reports go, a scheduled
    # job (whenever or sidekiq-cron, whichever the app already uses), and a
    # token-protected manual-trigger route. See the plan this implements:
    # production automation with zero ongoing DevOps dependency -- a normal
    # `git commit` + deploy is the only step after this generator runs.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_initializer
        template "initializer.rb.tt", "config/initializers/schema_reaper.rb"
      end

      def create_manual_trigger
        template "schema_reaper_controller.rb.tt", "app/controllers/schema_reaper_controller.rb"
        route "post '/internal/schema_scan', to: 'schema_reaper#trigger'"
      end

      def add_schedule
        case detected_scheduler
        when :whenever then add_whenever_schedule
        when :sidekiq_cron then add_sidekiq_cron_schedule
        else
          say_status :skip, "no `whenever` or `sidekiq-cron` gem detected -- add a cron entry yourself " \
                            "that runs `rake schema_reaper:alert` on whatever cadence you want", :yellow
        end
      end

      def warn_if_dev_scoped
        return unless gemfile_scopes_schema_reaper_to_dev?

        say_status :warning,
                   "schema_reaper is Gemfile-scoped to group: :development. Most production deploy " \
                   "pipelines strip dev/test groups (`bundle install --without development test`), so " \
                   "the scheduled scan will not run in production until you remove that restriction.",
                   :red
      end

      def print_token_instructions
        token = "#{app_identifier}-#{SecureRandom.hex(32)}"

        say ""
        say "Manual trigger token (shown once -- store it now):", :green
        say "  #{token}"
        say ""
        say "This is genuinely sensitive (it authorizes a production action), so it does not go in a " \
            "committed file. Store it in encrypted credentials instead:"
        say ""
        say "  rails credentials:edit"
        say ""
        say "and add:"
        say ""
        say "  schema_reaper:"
        say "    trigger_token: #{token}"
        say ""
        say "Trigger a scan on demand with:"
        say ""
        say "  curl -X POST https://your-app.example.com/internal/schema_scan \\"
        say "    -H \"Authorization: Bearer #{token}\""
        say ""
      end

      private

      def detected_scheduler
        return :whenever if gem_locked?("whenever")
        return :sidekiq_cron if gem_locked?("sidekiq-cron")

        nil
      end

      def gem_locked?(name)
        Bundler.locked_gems&.specs&.any? { |s| s.name == name } || false
      rescue StandardError
        false
      end

      def add_whenever_schedule
        path = "config/schedule.rb"
        entry = <<~RUBY

          every 3.months do
            rake "schema_reaper:alert"
          end
        RUBY

        if File.exist?(File.join(destination_root, path))
          append_to_file path, entry
        else
          create_file path, "require \"whenever\"\n#{entry}"
        end
      end

      def add_sidekiq_cron_schedule
        path = "config/schedule.yml"
        entry = <<~YAML

          schema_reaper_scan:
            cron: "0 4 1 */3 *" # 4am on the 1st, every 3 months
            class: "SchemaReaper::ScanJob"
            queue: default
        YAML

        if File.exist?(File.join(destination_root, path))
          append_to_file path, entry
        else
          create_file path, entry.sub("\n\n", "")
        end
      end

      # `gem "schema_reaper", group: :development` in the app's own Gemfile
      # -- see README's current install snippet. A dev-scoped gem is absent
      # from `bundle install --without development test`, which most
      # production deploy pipelines run, so the scheduled scan silently
      # never runs.
      def gemfile_scopes_schema_reaper_to_dev?
        gemfile = File.join(destination_root, "Gemfile")
        return false unless File.exist?(gemfile)

        File.readlines(gemfile).any? do |line|
          line.match?(/gem\s+["']schema_reaper["']/) && line.include?(":development")
        end
      end

      def app_identifier
        Rails.application.class.module_parent_name.underscore
      rescue StandardError
        "app"
      end
    end
  end
end
