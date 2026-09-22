# frozen_string_literal: true

RSpec.describe SchemaReaper::AlertConfig do
  after { described_class.reset! }

  it "starts unconfigured" do
    expect(described_class.instance).not_to be_configured
    expect(described_class.instance).not_to be_emails
    expect(described_class.instance).not_to be_webhook
  end

  it "is configured once emails are set, even with no webhook" do
    described_class.configure { |c| c.emails = ["dev@example.com"] }
    expect(described_class.instance).to be_configured
    expect(described_class.instance).to be_emails
    expect(described_class.instance).not_to be_webhook
  end

  it "is configured once a webhook_url is set, even with no emails" do
    described_class.configure { |c| c.webhook_url = "https://hooks.slack.com/services/x" }
    expect(described_class.instance).to be_configured
    expect(described_class.instance).to be_webhook
    expect(described_class.instance).not_to be_emails
  end

  it "treats a blank webhook_url as not configured" do
    described_class.configure { |c| c.webhook_url = "   " }
    expect(described_class.instance).not_to be_webhook
  end

  it "is a singleton shared across configure calls" do
    described_class.configure { |c| c.emails = ["a@example.com"] }
    described_class.configure { |c| c.webhook_url = "https://example.com/hook" }

    expect(described_class.instance.emails).to eq(["a@example.com"])
    expect(described_class.instance.webhook_url).to eq("https://example.com/hook")
  end
end
