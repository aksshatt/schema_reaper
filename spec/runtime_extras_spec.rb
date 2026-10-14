# frozen_string_literal: true

require "tmpdir"

RSpec.describe "runtime log extras" do
  describe SchemaReaper::Runtime::Report do
    it "spans min..max timestamps even when lines are out of order" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "runtime.jsonl")
        File.write(path, <<~JSONL)
          {"key":"users.email","at":"2026-01-10T00:00:00Z"}
          {"key":"users.name","at":"2026-01-01T00:00:00Z"}
          {"key":"users.email","at":"2026-01-05T00:00:00Z"}
        JSONL

        expect(described_class.load(path).observed_days).to eq(9)
      end
    end

    it "reads the rotated generation too" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "runtime.jsonl")
        File.write("#{path}.1", %({"key":"users.old","at":"2026-01-01T00:00:00Z"}\n))
        File.write(path, %({"key":"users.new","at":"2026-01-20T00:00:00Z"}\n))

        report = described_class.load(path)
        expect(report.accessed).to include("users.old", "users.new")
        expect(report.observed_days).to eq(19)
      end
    end
  end

  describe SchemaReaper::Runtime::Store do
    it "rotates the log to <path>.1 once it passes max_bytes" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "runtime.jsonl")
        store = described_class.new(path: path, flush_every: 1, max_bytes: 100)
        3.times { |i| store.record("users", "col#{i}") }

        expect(File.exist?("#{path}.1")).to be(true)
        expect(File.size?(path).to_i).to be <= 100
      end
    end

    it "never rotates when max_bytes is nil" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "runtime.jsonl")
        store = described_class.new(path: path, flush_every: 1, max_bytes: nil)
        5.times { |i| store.record("users", "col#{i}") }

        expect(File.exist?("#{path}.1")).to be(false)
      end
    end
  end

  describe SchemaReaper::Runtime::Tracker do
    around do |example|
      store = described_class.store
      rate = described_class.sample_rate
      example.run
      described_class.store = store
      described_class.sample_rate = rate
    end

    let(:recorded) { [] }

    before do
      fake = Object.new
      sink = recorded
      fake.define_singleton_method(:record) { |t, c| sink << "#{t}.#{c}" }
      described_class.store = fake
      described_class.sample_rate = 1.0
    end

    it "records every table named in a raw SQL statement, schema-qualified ones included" do
      described_class.note_sql(
        'SELECT * FROM "audits" JOIN "billing"."invoices" ON true WHERE id IN (SELECT 1 FROM pg_class)'
      )
      expect(recorded).to contain_exactly("audits.*", "billing.invoices.*")
    end

    it "skips Rails' own schema queries" do
      described_class.note_sql("SELECT * FROM users", "SCHEMA")
      expect(recorded).to be_empty
    end
  end
end
