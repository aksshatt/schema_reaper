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
    allow(SchemaReaper::Notifier).to receive(:new).with([finding]).and_return(notifier)

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
end
