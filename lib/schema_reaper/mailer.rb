# frozen_string_literal: true

module SchemaReaper
  # Inherits ApplicationMailer when the host app defines one (the normal
  # case), so it picks up the app's own `default from:`, layout and delivery
  # settings automatically -- "reuse the app's already-configured mailer,
  # don't require a new SMTP setup" is the whole point of the email channel.
  # Falls back to ActionMailer::Base directly for apps that don't.
  class Mailer < (defined?(::ApplicationMailer) ? ::ApplicationMailer : ActionMailer::Base)
    def report_email(to:, report:)
      @report = report
      mail(to: to, subject: "[schema_reaper] scan report") do |format|
        format.text { render plain: @report }
      end
    end
  end
end
