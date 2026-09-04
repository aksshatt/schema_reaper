# frozen_string_literal: true

require "tmpdir"
require "stringio"
require "json"

RSpec.describe "supporting units" do
  let(:finding) do
    SchemaReaper::Finding.new(
      type: :dead_column, table: "users", column: "x", severity: :high,
      confidence: 0.9, bytes_per_row: 8, reclaimable_bytes: 8000,
      evidence: ["nothing references it"], suggested_fix: "drop it"
    )
  end

  describe SchemaReaper::Reporters::Bytes do
    it "renders human sizes" do
      expect(described_class.human(512)).to eq("512.0 B")
      expect(described_class.human(2048)).to eq("2.0 KB")
      expect(described_class.human(5 * 1024 * 1024)).to eq("5.0 MB")
    end
  end

  describe SchemaReaper::Reporters::Sarif do
    it "emits valid SARIF 2.1.0 with one result per finding" do
      io = StringIO.new
      described_class.new([finding], io: io).render
      doc = JSON.parse(io.string)
      expect(doc["version"]).to eq("2.1.0")
      expect(doc.dig("runs", 0, "results").length).to eq(1)
      expect(doc.dig("runs", 0, "results", 0, "level")).to eq("error")
    end
  end

  describe SchemaReaper::Reporters::Markdown do
    it "produces a table with the reclaim total" do
      io = StringIO.new
      described_class.new([finding], io: io).render
      expect(io.string).to include("## schema_reaper", "| Severity |", "7.8 KB")
    end
  end

  describe SchemaReaper::Baseline do
    it "reports only findings absent from the stored set" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "baseline.json")
        base = described_class.new(path)
        base.write([finding])
        other = finding.dup.tap { |f| f.column = "y" }
        expect(base.new_among([finding, other]).map(&:column)).to eq(["y"])
      end
    end
  end

  describe SchemaReaper::History do
    it "tracks count and byte deltas across snapshots" do
      Dir.mktmpdir do |dir|
        hist = described_class.new(File.join(dir, "history.jsonl"))
        hist.record([finding])
        hist.record([])
        trend = hist.trend
        expect(trend[:snapshots]).to eq(2)
        expect(trend[:count_change_total]).to eq(-1)
        expect(trend[:resolved_since_prev]).to include("dead_column/users/x")
      end
    end
  end

  describe SchemaReaper::Runtime::Report do
    it "loads a jsonl usage log and spans observed days" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "runtime.jsonl")
        File.write(path, <<~LINES)
          {"key":"users.email","at":"2026-01-01T00:00:00Z"}
          {"key":"users.email","at":"2026-01-20T00:00:00Z"}
        LINES
        report = described_class.load(path)
        expect(report.read?("users", "email")).to be(true)
        expect(report.read?("users", "gone")).to be(false)
        expect(report.observed_days).to eq(19)
      end
    end
  end

  describe SchemaReaper::GemAwareness do
    it "reserves gem columns only for installed gems and matching tables" do
      tables = [
        fake_table("users", columns: [{ name: "encrypted_password" }, { name: "uid" }]),
        fake_table("versions", columns: [{ name: "whodunnit" }, { name: "item_type" }]),
        fake_table("orders", columns: [{ name: "total" }, { name: "provider" }])
      ]
      reserved = described_class.reserved_columns(installed: %w[devise paper_trail], tables: tables)
      expect(reserved["users"]).to include("encrypted_password")
      expect(reserved["versions"]).to include("whodunnit")
      expect(reserved["orders"]).to be_empty
    end
  end
end
