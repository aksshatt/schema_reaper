# frozen_string_literal: true

require "tmpdir"

RSpec.describe "PR #26 review fixes: runtime and migrations" do
  describe SchemaReaper::Runtime::Store do
    # Two workers both saw an oversized log; the first rotates. The second
    # must re-check under the lock and leave the full generation in .1 alone.
    it "does not rotate a second time over a full older generation (mitkush #6)" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "runtime.jsonl")
        File.write(path, "x" * 500)
        a = described_class.new(path: path, max_bytes: 100)
        b = described_class.new(path: path, max_bytes: 100)

        allow(File).to receive(:size?).and_call_original
        a.send(:rotate_if_needed)
        File.write(path, "y" * 10) # a fresh, small log started by another worker
        # b's unlocked pre-check is stale: it still believes the log is big
        allow(File).to receive(:size?).with(path).and_return(500, 10)
        b.send(:rotate_if_needed)

        expect(File.read("#{path}.1")).to eq("x" * 500)
        expect(File.read(path)).to eq("y" * 10)
      end
    end
  end

  describe SchemaReaper::Runtime::Tracker do
    around do |ex|
      store = described_class.store
      rate = described_class.sample_rate
      ex.run
      described_class.store = store
      described_class.sample_rate = rate
    end

    it "does not count an INSERT target as read, but still counts INSERT ... SELECT sources" do
      seen = []
      fake = Object.new
      fake.define_singleton_method(:record) { |t, c| seen << "#{t}.#{c}" }
      described_class.store = fake
      described_class.sample_rate = 1.0

      described_class.note_sql('INSERT INTO "audit_logs" ("a") VALUES ($1)')
      described_class.note_sql('INSERT INTO "archive" SELECT * FROM "orders"')
      expect(seen).to eq(["orders.*"])
    end
  end

  describe SchemaReaper::Runtime::Report do
    it "takes the span from string-sorted ISO8601 timestamps without parsing every line" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "runtime.jsonl")
        File.write(path, <<~JSONL)
          {"key":"a.b","at":"2026-03-01T00:00:00Z"}
          {"key":"a.c","at":"2026-01-01T00:00:00Z"}
          {"key":"a.d","at":null}
        JSONL
        allow(Time).to receive(:parse).and_call_original

        expect(described_class.load(path).observed_days).to eq(59)
        expect(Time).to have_received(:parse).twice
      end
    end
  end

  describe SchemaReaper::MigrationGenerator do
    it "makes the index migration check for a partitioned index at run time (mitkush #3)" do
      Dir.mktmpdir do |dir|
        src = File.read(described_class.new(table: "billing.events", index: "ev_k", dir: dir).call.first)

        expect(RubyVM::InstructionSequence.compile(src)).to be_a(RubyVM::InstructionSequence)
        expect(src).to include("def partitioned_index?", "to_regclass(\#{connection.quote(\"billing.ev_k\")})")
        expect(src).to include('remove_index :"billing.events", name: :ev_k, if_exists: true')
      end
    end
  end

  describe "partitioned index advice" do
    it "does not suggest CONCURRENTLY for a partitioned index" do
      table = fake_table("events", columns: [{ name: "id" }, { name: "kind" }],
                                   indexes: [{ name: "ev_kind", columns: %w[kind], scans: 0 }])
      table.indexes.first.partitioned = true
      f = SchemaReaper::Analyzers::UnusedIndex.new(context_for(schema: fake_schema(table))).call.first

      expect(f.suggested_fix).not_to include("algorithm: :concurrently")
      expect(f.suggested_fix).to include("partitioned index")
    end
  end
end
