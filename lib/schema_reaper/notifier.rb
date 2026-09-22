# frozen_string_literal: true

require "net/http"
require "json"
require "stringio"
require_relative "reporters/markdown"

module SchemaReaper
  # Delivers a completed scan's findings through whichever channels are
  # configured in AlertConfig -- a Slack-compatible webhook POST and/or email
  # via the host app's own ActionMailer setup. Both fire when both are
  # configured; this isn't a fallback chain (schema reports aren't critical
  # enough to need one), it's reaching two different audiences: a dev-facing
  # chat channel and a more formal inbox record for people who don't watch
  # chat.
  #
  # Delivery failures are logged, never raised -- a webhook endpoint being
  # briefly down should not fail the scan job or retry-storm it.
  class Notifier
    def initialize(findings, config: AlertConfig.instance, http: Net::HTTP, mailer: nil)
      @findings = findings
      @config = config
      @http = http
      @mailer = mailer || (defined?(Mailer) ? Mailer : nil)
    end

    def deliver
      return unless @config.configured?

      deliver_webhook if @config.webhook?
      deliver_email if @config.emails?
    end

    private

    def report_text
      @report_text ||= begin
        io = StringIO.new
        Reporters::Markdown.new(@findings, io: io).render
        io.string
      end
    end

    # Slack's incoming-webhook shape ({"text": ...}) is the most common
    # receiver in practice; Discord's legacy webhook path also accepts a
    # plain "content" body but that's a different key, and structured-alert
    # services like PagerDuty need an entirely different schema (their
    # Events API v2, not a text webhook) -- those need a different endpoint,
    # not this one.
    def deliver_webhook
      uri = URI.parse(@config.webhook_url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(text: report_text)

      client = @http.new(uri.host, uri.port)
      client.use_ssl = uri.scheme == "https"
      client.request(request)
    rescue StandardError => e
      log_error("webhook delivery failed", e)
    end

    def deliver_email
      unless @mailer
        log_error("email delivery skipped", "SchemaReaper::Mailer is not loaded (ActionMailer not present?)")
        return
      end

      @mailer.report_email(to: @config.emails, report: report_text).deliver_later
    rescue StandardError => e
      log_error("email delivery failed", e)
    end

    def log_error(message, error)
      detail = error.is_a?(Exception) ? "#{error.class}: #{error.message}" : error.to_s
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.error("[schema_reaper] #{message}: #{detail}")
      else
        warn("[schema_reaper] #{message}: #{detail}")
      end
    end
  end
end
