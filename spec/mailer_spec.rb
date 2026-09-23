# frozen_string_literal: true

require "open3"

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

  # Without a from address, mail() raises "SMTP From address may not be
  # blank" -- and critically, that happens inside the background job when it
  # actually renders the message (deliver_later only enqueues), not inside
  # Notifier#deliver_email's rescue. An app with no ApplicationMailer, which
  # is exactly this spec's own environment, hits this path for real.
  it "falls back to a placeholder from: address so delivery does not raise when no ApplicationMailer sets one" do
    expect(described_class.default_params[:from]).to be_present

    expect do
      described_class.report_email(to: ["dev@example.com"], report: "x").deliver_now
    end.not_to raise_error
  end

  # The bug this guards against only exists across a real boot order, so it
  # runs in a fresh process: in a Rails app the gem is required (Bundler.require)
  # before the app's autoloader can see app/mailers/application_mailer.rb.
  it "inherits an ApplicationMailer that is only defined after the gem is required" do
    script = <<~RUBY
      require "action_mailer"
      require "schema_reaper"
      class ApplicationMailer < ActionMailer::Base
        default from: "team@app.example"
      end
      print [SchemaReaper::Mailer.superclass, SchemaReaper::Mailer.default_params[:from]].join(",")
    RUBY
    lib = File.expand_path("../lib", __dir__)
    output, status = Open3.capture2e(RbConfig.ruby, "-I", lib, "-e", script)

    expect(status).to be_success, output
    expect(output).to eq("ApplicationMailer,team@app.example")
  end
end
