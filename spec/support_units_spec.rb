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

  describe SchemaReaper::DatabaseSchema do
    def schema_with(total, index_count)
      indexes = Array.new(index_count) { |i| { name: "idx_#{i}", columns: ["c#{i}"] } }
      fake_schema(
        fake_table("t", columns: [{ name: "id" }], indexes: indexes),
        index_scan_total: total
      )
    end

    it "assumes stats are usable when the introspector reports no total" do
      expect(schema_with(nil, 10).query_history?).to be(true)
    end

    it "treats fewer scans than indexes as no query history" do
      expect(schema_with(2, 10).query_history?).to be(false)
    end

    it "treats at least one scan per index as query history" do
      expect(schema_with(10, 10).query_history?).to be(true)
    end
  end

  describe "Table#primary_key?" do
    it "accepts a single primary key name" do
      table = fake_table("users", primary_key: "id", columns: [{ name: "id" }])
      expect(table.primary_key?("id")).to be(true)
      expect(table.primary_key?("email")).to be(false)
    end

    it "accepts every column of a composite primary key" do
      table = fake_table("memberships", primary_key: %w[user_id group_id],
                                        columns: [{ name: "user_id" }, { name: "group_id" }])
      expect(table.primary_key_columns).to eq(%w[user_id group_id])
      expect(table.primary_key?("user_id")).to be(true)
      expect(table.primary_key?("group_id")).to be(true)
    end

    it "treats a missing primary key as no columns" do
      table = fake_table("logs", primary_key: nil, columns: [{ name: "id" }])
      expect(table.primary_key_columns).to eq([])
      expect(table.primary_key?("id")).to be(false)
    end
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

    it "names tables a gem owns outright, but not tables it only adds columns to" do
      owned = described_class.owned_tables(installed: %w[activeadmin devise-api devise])
      expect(owned).to include("active_admin_comments", "devise_api_tokens")
      # devise's own entry is a "*" glob (columns added onto whatever table has
      # them, e.g. users) -- it does not own any specific table outright.
      expect(owned).not_to include("*")
    end

    it "names nothing for a gem that is not installed" do
      expect(described_class.owned_tables(installed: %w[devise])).to be_empty
    end

    describe ".installed_gems" do
      # Every other example above passes installed: explicitly, so this is
      # the only spec that exercises the real detection Runner actually uses
      # in production.
      it "lists real gems from this project's own bundle via Bundler" do
        names = described_class.installed_gems
        expect(names).to include("rspec", "prism") # gems this gemspec/Gemfile actually declares
      end

      it "falls back to Gem::Specification when Bundler is not defined" do
        hide_const("Bundler")
        names = described_class.installed_gems
        expect(names).to include("rspec-core")
      end

      it "returns an empty list instead of raising if gem detection itself blows up" do
        allow(Bundler).to receive(:load).and_raise(StandardError, "corrupt lockfile")
        expect(described_class.installed_gems).to eq([])
      end
    end
  end
end
