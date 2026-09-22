# frozen_string_literal: true

RSpec.describe SchemaReaper::Mailer do
  around do |example|
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.deliveries.clear
    example.run
  end

  it "inherits ActionMailer::Base directly when the host app has no ApplicationMailer" do
    expect(described_class.ancestors).to include(ActionMailer::Base)
  end

  it "builds a plain-text email addressed to every configured recipient" do
    mail = described_class.report_email(
      to: %w[dev1@example.com dev2@example.com],
      report: "## schema_reaper\n\nNo findings."
    )

    expect(mail.to).to eq(%w[dev1@example.com dev2@example.com])
    expect(mail.subject).to eq("[schema_reaper] scan report")
    expect(mail.body.encoded).to include("No findings")
  end
end
