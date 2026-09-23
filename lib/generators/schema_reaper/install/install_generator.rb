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

        # `route` (unlike `template`/`create_file`) has no conflict
        # detection of its own -- it unconditionally injects, so re-running
        # this generator would duplicate the line every time without this
        # guard.
        routes_path = File.join(destination_root, "config/routes.rb")
        if File.exist?(routes_path) && File.read(routes_path).include?("schema_reaper#trigger")
          say_status :skip, "config/routes.rb already routes to schema_reaper#trigger -- not duplicating it", :yellow
        else
          route "post '/internal/schema_scan', to: 'schema_reaper#trigger'"
        end
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
                   "pipelines strip dev/test groups (`BUNDLE_WITHOUT=development:test`), so " \
                   "the scheduled scan will not run in production until you remove that restriction.",
                   :red
      end

      def warn_if_no_mailer_from
        return if mailer_from_configured?

        say_status :warning,
                   "no ApplicationMailer default `from:` detected (nor config.action_mailer.default_options). " \
                   "SchemaReaper::Mailer falls back to a " \
                   "placeholder sender in that case, which most real SMTP relays reject or spam-flag -- " \
                   "email reports would silently fail to arrive. If you plan to use the email channel " \
                   "(config.emails in the initializer this generator just wrote), set " \
                   "`default from: \"...\"` on ApplicationMailer first.",
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
        marker = 'rake "schema_reaper:alert"'
        entry = <<~RUBY

          every 3.months do
            #{marker}
          end
        RUBY

        full_path = File.join(destination_root, path)
        if File.exist?(full_path) && File.read(full_path).include?(marker)
          say_status :skip, "#{path} already has a schema_reaper entry -- not duplicating it", :yellow
        elsif File.exist?(full_path)
          append_to_file path, entry
        else
          # No `require "whenever"` here -- real wheneverize-generated files
          # don't have one; whenever's own CLI evaluates this file through
          # its DSL, not as a plain script that needs to load itself.
          create_file path, entry.sub("\n\n", "")
        end
      end

      def add_sidekiq_cron_schedule
        path = "config/schedule.yml"
        marker = "schema_reaper_scan:"
        entry = <<~YAML

          #{marker}
            cron: "0 4 1 */3 *" # 4am on the 1st, every 3 months
            class: "SchemaReaper::ScanJob"
            queue: default
            active_job: true # explicit, not relying on class-ancestry auto-detection
        YAML

        full_path = File.join(destination_root, path)
        if File.exist?(full_path) && File.read(full_path).include?(marker)
          say_status :skip, "#{path} already has a schema_reaper_scan entry -- not duplicating it", :yellow
        elsif File.exist?(full_path)
          append_to_file path, entry
        else
          create_file path, entry.sub("\n\n", "")
        end
      end

      # `gem "schema_reaper", group: :development` (or the equivalent
      # `group :development do ... end` block form) in the app's own Gemfile
      # -- see README's current install snippet. A dev-scoped gem is absent
      # from `BUNDLE_WITHOUT=development:test` installs, which most
      # production deploy pipelines run, so the scheduled scan silently
      # never runs.
      #
      # Parsed with Bundler's own DSL rather than line-scanning for
      # "group: :development" -- a regex over raw lines misses the block
      # form entirely (the gem's own line never mentions :development; the
      # `group :development do` line above it does), and that block form is
      # the more common style in practice, not an edge case.
      def gemfile_scopes_schema_reaper_to_dev?
        gemfile = File.join(destination_root, "Gemfile")
        return false unless File.exist?(gemfile)

        dep = Bundler::Dsl.evaluate(gemfile, nil, {}).dependencies.find { |d| d.name == "schema_reaper" }
        dep && !dep.groups.include?(:default)
      rescue StandardError
        false # a Gemfile we can't parse shouldn't block the rest of the generator
      end

      # Checked against the class SchemaReaper::Mailer will inherit from --
      # ApplicationMailer when the app has one, ActionMailer::Base otherwise
      # (where `config.action_mailer.default_options = { from: ... }` lands).
      # At generate time the app is already booted, so this reads the same
      # `default_params[:from]` chain Mailer itself will see.
      def mailer_from_configured?
        parent = defined?(::ApplicationMailer) ? ::ApplicationMailer : ::ActionMailer::Base
        parent.default_params[:from].present?
      rescue StandardError
        true # can't determine -- don't nag over something we're unsure about
      end

      def app_identifier
        Rails.application.class.module_parent_name.underscore
      rescue StandardError
        "app"
      end
    end
  end
end
