# frozen_string_literal: true

require "net/http"
require "json"
require "stringio"
require_relative "reporters/markdown"
require_relative "reporters/slack"
require_relative "alert_state"

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
    def initialize(findings, config: AlertConfig.instance, http: Net::HTTP, mailer: :auto, mail_delivery: :later,
                   state: AlertState.new)
      @findings = findings
      @config = config
      @http = http
      @mailer = mailer == :auto ? default_mailer : mailer
      @mail_delivery = mail_delivery
      @state = state
    end

    def deliver
      return unless @config.configured?
      return if @config.changes_only? && unchanged?

      sent = [(deliver_webhook if @config.webhook?), (deliver_email if @config.emails?)]
      # Only a report someone received becomes the baseline for "what
      # changed" -- otherwise a failed delivery would make the next run
      # think it was already reported, and alert_on: :changes would stay
      # silent about it.
      @state.remember(@findings.map(&:id)) if sent.any?
      sent.any?
    end

    private

    # {new:, resolved:} against the last delivered report, or nil when there
    # is none to compare with.
    def changes
      return @changes if defined?(@changes)

      prev = @state.previous_ids
      @changes = prev && {
        new: @findings.reject { |f| prev.include?(f.id) },
        resolved: prev - @findings.map(&:id)
      }
    end

    # A first report (nothing to compare with) always goes out.
    def unchanged?
      !changes.nil? && changes[:new].empty? && changes[:resolved].empty?
    end

    def webhook_body
      return Reporters::Slack.new(@findings, changes: changes).payload if @config.slack_blocks?

      { text: report_text }
    end

    # Mailer is autoloaded (see lib/schema_reaper.rb), and it can only be
    # defined when ActionMailer is present -- check that, not Mailer itself.
    def default_mailer
      defined?(::ActionMailer::Base) ? Mailer : nil
    end

    def report_text
      @report_text ||= begin
        io = StringIO.new
        io.puts(changes_text) if changes
        Reporters::Markdown.new(@findings, io: io).render
        io.string
      end
    end

    def changes_text
      lines = ["**Since the last report:** #{changes[:new].size} new, #{changes[:resolved].size} resolved"]
      lines += changes[:new].map { |f| "- new: `#{f.id}`" }
      lines += changes[:resolved].map { |id| "- resolved: `#{id}`" }
      "#{lines.join("\n")}\n"
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
      request.body = JSON.generate(webhook_body)

      client = @http.new(uri.host, uri.port)
      client.use_ssl = uri.scheme == "https"
      # A background job blocking indefinitely on a dead webhook host would
      # back up the queue behind it -- bound the wait instead of relying on
      # Net::HTTP's own (version-dependent) defaults.
      client.open_timeout = 10
      client.read_timeout = 10
      accepted?(client.request(request))
    rescue StandardError => e
      log_error("webhook delivery failed", e)
      false
    end

    # Slack answers a bad payload with 400 invalid_blocks, not an exception.
    def accepted?(response)
      return true unless response.respond_to?(:code) && !response.code.to_s.start_with?("2")

      log_error("webhook delivery failed", "HTTP #{response.code}: #{response.body.to_s[0, 200]}")
      false
    end

    def deliver_email
      unless @mailer
        log_error("email delivery skipped", "SchemaReaper::Mailer is not loaded (ActionMailer not present?)")
        return false
      end

      message = @mailer.report_email(to: @config.emails, report: report_text)
      @mail_delivery == :now ? message.deliver_now : message.deliver_later
      true
    rescue StandardError => e
      log_error("email delivery failed", e)
      false
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
