# frozen_string_literal: true

module SchemaReaper
  # Inherits ApplicationMailer when the host app defines one (the normal
  # case), so it picks up the app's own `default from:`, layout and delivery
  # settings automatically -- "reuse the app's already-configured mailer,
  # don't require a new SMTP setup" is the whole point of the email channel.
  # Falls back to ActionMailer::Base directly for apps that don't.
  class Mailer < (defined?(::ApplicationMailer) ? ::ApplicationMailer : ActionMailer::Base)
    # Only applied when nothing upstream (ApplicationMailer or its own
    # ancestors) already set one. Without this, `mail()` raises "SMTP From
    # address may not be blank" -- and Notifier's rescue never sees it:
    # deliver_later only enqueues, the actual render/from-validation happens
    # later inside ActionMailer::MailDeliveryJob#perform, so an app that
    # hits this path gets a bare, unbranded ActiveJob failure with no
    # `[schema_reaper]` log line anywhere near it. This placeholder isn't a
    # real deliverable address -- most SMTP relays will still reject or
    # spam-flag mail from an unconfigured sender -- it only turns a hard
    # crash into a normal delivery failure. The install generator warns at
    # setup time when this fallback would apply, so the real fix (configure
    # a `default from:`) doesn't have to be discovered from a stack trace.
    default from: "schema_reaper@localhost" unless default_params[:from]

    def report_email(to:, report:)
      @report = report
      mail(to: to, subject: "[schema_reaper] scan report") do |format|
        format.text { render plain: @report }
      end
    end
  end
end
