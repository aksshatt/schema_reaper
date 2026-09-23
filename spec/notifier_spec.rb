# frozen_string_literal: true

RSpec.describe SchemaReaper::Notifier do
  let(:finding) do
    SchemaReaper::Finding.new(
      type: :dead_column, table: "users", column: "legacy", severity: :medium,
      confidence: 0.6, bytes_per_row: 8, reclaimable_bytes: 8000,
      evidence: ["nothing references it"], suggested_fix: "drop it"
    )
  end
  let(:config) { SchemaReaper::AlertConfig.new }

  describe "with nothing configured" do
    it "sends nothing and does not raise" do
      http = class_spy(Net::HTTP)
      described_class.new([finding], config: config, http: http).deliver
      expect(http).not_to have_received(:new)
    end
  end

  it "auto-detects the real SchemaReaper::Mailer when mailer: is not given at all" do
    config.emails = ["dev@example.com"]
    notifier = described_class.new([finding], config: config)

    expect(notifier.send(:instance_variable_get, :@mailer)).to eq(SchemaReaper::Mailer)
  end

  it "logs through Rails.logger instead of warn when a real Rails logger is present" do
    logger = instance_double(Logger, error: nil)
    allow(Rails).to receive(:logger).and_return(logger)
    config.emails = ["dev@example.com"]

    described_class.new([finding], config: config, mailer: nil).deliver

    expect(logger).to have_received(:error).with(/email delivery skipped/)
  end

  describe "webhook delivery" do
    let(:http_client) { instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil, request: nil) }
    let(:http) { class_double(Net::HTTP, new: http_client) }

    before { config.webhook_url = "https://hooks.slack.com/services/T000/B000/XXXX" }

    it "POSTs a Slack-compatible {text:} body to the configured URL" do
      described_class.new([finding], config: config, http: http).deliver

      expect(http).to have_received(:new).with("hooks.slack.com", 443)
      expect(http_client).to have_received(:request) do |req|
        expect(req["Content-Type"]).to eq("application/json")
        body = JSON.parse(req.body)
        expect(body["text"]).to include("dead_column", "users", "legacy")
      end
    end

    it "bounds the wait instead of letting a dead webhook host hang the job indefinitely" do
      described_class.new([finding], config: config, http: http).deliver

      expect(http_client).to have_received(:open_timeout=).with(10)
      expect(http_client).to have_received(:read_timeout=).with(10)
    end

    it "logs and swallows a delivery failure instead of raising" do
      allow(http_client).to receive(:request).and_raise(Errno::ECONNREFUSED)
      notifier = described_class.new([finding], config: config, http: http)

      expect { notifier.deliver }.not_to raise_error
    end

    it "does not attempt email delivery when only a webhook is configured" do
      mailer = class_spy("SchemaReaper::Mailer")
      described_class.new([finding], config: config, http: http, mailer: mailer).deliver

      expect(mailer).not_to have_received(:report_email)
    end
  end

  describe "email delivery" do
    let(:mail_message) { instance_double(ActionMailer::MessageDelivery, deliver_later: true) }
    let(:mailer) { class_double("SchemaReaper::Mailer", report_email: mail_message) }

    before { config.emails = %w[dev1@example.com dev2@example.com] }

    it "renders the findings as Markdown and hands it to the mailer, then delivers later" do
      described_class.new([finding], config: config, mailer: mailer).deliver

      expect(mailer).to have_received(:report_email) do |kwargs|
        expect(kwargs[:to]).to eq(%w[dev1@example.com dev2@example.com])
        expect(kwargs[:report]).to include("dead_column", "users", "legacy")
      end
      expect(mail_message).to have_received(:deliver_later)
    end

    it "logs instead of raising when no mailer is available" do
      notifier = described_class.new([finding], config: config, mailer: nil)
      expect { notifier.deliver }.not_to raise_error
    end

    it "logs and swallows a delivery failure instead of raising" do
      allow(mailer).to receive(:report_email).and_raise(StandardError, "smtp down")
      notifier = described_class.new([finding], config: config, mailer: mailer)

      expect { notifier.deliver }.not_to raise_error
    end
  end

  it "fires both channels when both are configured" do
    config.webhook_url = "https://hooks.slack.com/services/T000/B000/XXXX"
    config.emails = ["dev@example.com"]
    http_client = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil, request: nil)
    http = class_double(Net::HTTP, new: http_client)
    mail_message = instance_double(ActionMailer::MessageDelivery, deliver_later: true)
    mailer = class_double("SchemaReaper::Mailer", report_email: mail_message)

    described_class.new([finding], config: config, http: http, mailer: mailer).deliver

    expect(http_client).to have_received(:request)
    expect(mailer).to have_received(:report_email)
  end
end
