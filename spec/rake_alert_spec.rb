# frozen_string_literal: true

require "rake"

RSpec.describe "rake schema_reaper:alert" do
  let(:rake) { Rake::Application.new }

  before do
    Rake.application = rake
    Rake::Task.define_task(:environment)
    load File.expand_path("../lib/schema_reaper/tasks/schema_reaper.rake", __dir__)
    allow(SchemaReaper::ScanJob).to receive(:perform_later)
    allow(SchemaReaper::ScanJob).to receive(:perform_now)
  end

  after { Rake.application = Rake::Application.new }

  it "enqueues the scan when a real job backend will run it" do
    allow(SchemaReaper::ScanJob).to receive(:in_process_queue?).and_return(false)
    rake["schema_reaper:alert"].invoke

    expect(SchemaReaper::ScanJob).to have_received(:perform_later)
    expect(SchemaReaper::ScanJob).not_to have_received(:perform_now)
  end

  # On :async the job would run on a thread in this rake process, which exits
  # as soon as the task returns -- the scan would silently never happen.
  it "runs the scan inline, mail included, on the in-process :async adapter" do
    allow(SchemaReaper::ScanJob).to receive(:in_process_queue?).and_return(true)
    expect { rake["schema_reaper:alert"].invoke }.to output(/running the scan inline/).to_stdout

    expect(SchemaReaper::ScanJob).to have_received(:perform_now).with(deliver_mail_now: true)
    expect(SchemaReaper::ScanJob).not_to have_received(:perform_later)
  end
end
