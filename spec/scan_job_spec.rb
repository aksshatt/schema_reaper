# frozen_string_literal: true

RSpec.describe SchemaReaper::ScanJob do
  it "runs a scan and hands the findings to Notifier" do
    finding = SchemaReaper::Finding.new(
      type: :dead_table, table: "ghost", column: nil, severity: :high,
      confidence: 0.5, bytes_per_row: 0, reclaimable_bytes: nil,
      evidence: ["nothing references it"], suggested_fix: "drop it"
    )
    runner = instance_double(SchemaReaper::Runner, run: [finding])
    notifier = instance_double(SchemaReaper::Notifier, deliver: nil)
    allow(SchemaReaper::Runner).to receive(:new).and_return(runner)
    allow(SchemaReaper::Notifier).to receive(:new).with([finding], mail_delivery: :later).and_return(notifier)

    described_class.perform_now

    expect(runner).to have_received(:run)
    expect(notifier).to have_received(:deliver)
  end

  it "can be enqueued like any other ActiveJob" do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    described_class.perform_later

    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
    expect(enqueued.map { |j| j[:job] }).to include(described_class)
  end

  it "sends mail immediately when run inline with deliver_mail_now" do
    allow(SchemaReaper::Runner).to receive(:new).and_return(instance_double(SchemaReaper::Runner, run: []))
    notifier = instance_double(SchemaReaper::Notifier, deliver: nil)
    allow(SchemaReaper::Notifier).to receive(:new).with([], mail_delivery: :now).and_return(notifier)

    described_class.perform_now(deliver_mail_now: true)

    expect(notifier).to have_received(:deliver)
  end

  describe ".in_process_queue?" do
    it "is true on the :async adapter, whose jobs die with the enqueueing process" do
      allow(described_class).to receive(:queue_adapter).and_return(ActiveJob::QueueAdapters::AsyncAdapter.new)
      expect(described_class.in_process_queue?).to be(true)
    end

    it "is false on an adapter backed by a separate worker" do
      expect(described_class.in_process_queue?).to be(false) # the suite's :test adapter
    end
  end
end
