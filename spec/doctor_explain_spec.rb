# frozen_string_literal: true

require "tmpdir"
require "stringio"

RSpec.describe "doctor and explain" do
  let(:out) { StringIO.new }
  let(:console) { SchemaReaper::Reporters::Console.new(out: out, err: out, color: false) }

  def config(dir, extra = {})
    SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.merge(
      "scan_paths" => [], "runtime_log" => File.join(dir, "rt.jsonl"),
      "baseline" => File.join(dir, "baseline.json")
    ).merge(extra))
  end

  describe SchemaReaper::Doctor do
    def introspector(diag, schema: fake_schema(index_scan_total: 0))
      double("introspector", diagnostics: diag, call: schema)
    end

    let(:healthy) do
      { server_version: "16.2", stats_reset: (Time.now - (30 * 86_400)).to_s, never_analyzed: [], in_recovery: false }
    end

    it "passes with warnings, naming each problem" do
      Dir.mktmpdir do |dir|
        diag = healthy.merge(stats_reset: Time.now.to_s, never_analyzed: %w[users orders], in_recovery: true)
        ok = described_class.new(config: config(dir), root: dir, introspector: introspector(diag),
                                 console: console).call

        expect(ok).to be(true)
        expect(out.string).to include("PostgreSQL 16.2", "reset 0 day(s) ago", "2 table(s) never analysed",
                                      "read replica", "none at")
      end
    end

    it "fails when the database can't be reached" do
      Dir.mktmpdir do |dir|
        broken = double("introspector")
        allow(broken).to receive(:diagnostics).and_raise(SchemaReaper::Error, "could not connect")
        ok = described_class.new(config: config(dir), root: dir, introspector: broken, console: console).call

        expect(ok).to be(false)
        expect(out.string).to include("✗ database", "could not connect", "1 failed")
      end
    end

    it "reports a long-enough runtime log and expired baseline entries" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "rt.jsonl"), <<~JSONL)
          {"key":"users.email","at":"2026-01-01T00:00:00Z"}
          {"key":"users.name","at":"2026-02-01T00:00:00Z"}
        JSONL
        cfg = config(dir)
        f = SchemaReaper::Finding.new(type: :dead_column, table: "users", column: "x", severity: :low,
                                      confidence: 0.5, evidence: [], suggested_fix: "")
        SchemaReaper::Baseline.new(cfg.baseline_path).write([f], expires_on: Date.today - 1)

        described_class.new(config: cfg, root: dir, introspector: introspector(healthy), console: console).call
        expect(out.string).to include("31 day(s), 2 column(s) seen", "1 entry has expired: dead_column/users/x")
      end
    end
  end

  describe SchemaReaper::Explain do
    let(:findings) do
      [
        SchemaReaper::Finding.new(type: :dead_column, table: "users", column: "legacy_token", severity: :high,
                                  confidence: 0.8, bytes_per_row: 8, reclaimable_bytes: 8000,
                                  evidence: ["no reference"], suggested_fix: "stage removal"),
        SchemaReaper::Finding.new(type: :unused_index, table: "users", column: "a", index: "idx_users_a",
                                  severity: :medium, confidence: 0.55, evidence: [], suggested_fix: "remove")
      ]
    end

    it "matches a partial id and prints the next command" do
      Dir.mktmpdir do |dir|
        expect(described_class.new(findings, config: config(dir), root: dir, console: console)
          .call("users/legacy_token")).to be(true)
        expect(out.string).to include("dead_column/users/legacy_token", "0.80", "7.8 KB", "no reference",
                                      "generate-migration users legacy_token", "not accepted")
      end
    end

    it "suggests --index for index findings" do
      Dir.mktmpdir do |dir|
        described_class.new(findings, config: config(dir), root: dir, console: console).call("idx_users_a")
        expect(out.string).to include("generate-migration users --index idx_users_a")
      end
    end

    it "lists candidates when the query is ambiguous, and fails" do
      Dir.mktmpdir do |dir|
        expect(described_class.new(findings, config: config(dir), root: dir, console: console).call("users"))
          .to be(false)
        expect(out.string).to include("2 findings match")
      end
    end
  end
end
