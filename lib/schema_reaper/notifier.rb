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
    # `mailer:` defaults to :auto rather than nil so an explicit
    # `mailer: nil` (forcing "no mailer available", e.g. to test that path,
    # or because a caller genuinely wants email delivery skipped) is
    # respected rather than silently falling back to the auto-detected
    # SchemaReaper::Mailer via `||`.
    #
    # `mail_delivery:` is :later (enqueue via ActiveJob, the normal case) or
    # :now -- for a caller that is itself running inline in a short-lived
    # process, where an in-process queue would be torn down before the mail
    # job ever ran (see the schema_reaper:alert rake task).
    def initialize(findings, config: AlertConfig.instance, http: Net::HTTP, mailer: :auto, mail_delivery: :later)
      @findings = findings
      @config = config
      @http = http
      @mailer = mailer == :auto ? default_mailer : mailer
      @mail_delivery = mail_delivery
    end

    def deliver
      return unless @config.configured?

      deliver_webhook if @config.webhook?
      deliver_email if @config.emails?
    end

    private

    # Mailer is autoloaded (see lib/schema_reaper.rb), and it can only be
    # defined when ActionMailer is present -- check that, not Mailer itself.
    def default_mailer
      defined?(::ActionMailer::Base) ? Mailer : nil
    end

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
      # A background job blocking indefinitely on a dead webhook host would
      # back up the queue behind it -- bound the wait instead of relying on
      # Net::HTTP's own (version-dependent) defaults.
      client.open_timeout = 10
      client.read_timeout = 10
      client.request(request)
    rescue StandardError => e
      log_error("webhook delivery failed", e)
    end

    def deliver_email
      unless @mailer
        log_error("email delivery skipped", "SchemaReaper::Mailer is not loaded (ActionMailer not present?)")
        return
      end

      message = @mailer.report_email(to: @config.emails, report: report_text)
      @mail_delivery == :now ? message.deliver_now : message.deliver_later
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
