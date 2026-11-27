# frozen_string_literal: true

module SchemaReaper
  # Where the production scan's report goes. Set once from a Rails
  # initializer (config/initializers/schema_reaper.rb), typically written by
  # `rails generate schema_reaper:install`:
  #
  #   SchemaReaper::AlertConfig.configure do |config|
  #     config.emails = %w[dev1@example.com dev2@example.com]
  #     config.webhook_url = "https://hooks.slack.com/services/T000/B000/XXXX"
  #   end
  #
  # Neither field is a secret -- leaking a teammate's email address or a
  # webhook URL isn't a meaningful security event -- so this is meant to be
  # committed to git directly. The manual-trigger token is not: that one
  # lives in Rails.application.credentials (see the install generator).
  class AlertConfig
    class << self
      def configure
        yield instance
      end

      def instance
        @instance ||= new
      end

      # Test helper -- config set in one example must not leak into the next.
      def reset!
        @instance = new
      end
    end

    # alert_on:       :always  -- send every scheduled report (the 2.0 behaviour)
    #                 :changes -- send only when findings appeared or were
    #                             resolved since the last report
    # webhook_format: :auto    -- Slack Block Kit for hooks.slack.com, plain
    #                             {"text": <markdown>} for anything else
    #                 :slack / :text to force one
    attr_accessor :emails, :webhook_url, :alert_on, :webhook_format

    def initialize
      @emails = []
      @webhook_url = nil
      @alert_on = :always
      @webhook_format = :auto
    end

    def changes_only?
      alert_on.to_s == "changes"
    end

    def slack_blocks?
      case webhook_format.to_s
      when "slack" then true
      when "text" then false
      else webhook_url.to_s.include?("hooks.slack.com")
      end
    end

    def emails?
      !emails.to_a.empty?
    end

    def webhook?
      !webhook_url.to_s.strip.empty?
    end

    # Whether Notifier has anywhere to send a report. A generator-scaffolded
    # but unfilled-in config (both fields left commented out) is a safe
    # no-op, not an error.
    def configured?
      emails? || webhook?
    end
  end
end
