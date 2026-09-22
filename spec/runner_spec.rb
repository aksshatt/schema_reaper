# frozen_string_literal: true

RSpec.describe SchemaReaper::Runner do
  let(:root) { File.expand_path("fixtures", __dir__) }
  let(:config) do
    SchemaReaper::Config.new(
      SchemaReaper::Config::DEFAULTS.merge(
        "scan_paths" => %w[app], "view_globs" => [], "gem_awareness" => false
      )
    )
  end

  let(:introspector) do
    double(call: fake_schema(
      fake_table("users", row_count: 20, columns: [
                   { name: "id" },
                   { name: "email" },
                   { name: "abandoned_flag", null: true }
                 ])
    ))
  end

  it "runs scan + analyzers end to end without a database" do
    findings = described_class.new(
      config: config, root: root, introspector: introspector,
      runtime: SchemaReaper::Runtime::Report.empty
    ).run

    dead = findings.select { |f| f.type == :dead_column }
    expect(dead.map(&:column)).to include("abandoned_flag")
    expect(dead.map(&:column)).not_to include("email")
  end

  # Every example above injects introspector:/runtime:, bypassing the real
  # fallback wiring entirely (schema -> Introspect::Postgres, runtime_report
  # -> Runtime::Report.load, gem_columns/gem_owned_tables -> GemAwareness).
  # That wiring is exactly what production actually runs through.
  describe "default wiring (no introspector:/runtime: injected)" do
    it "falls back to Introspect::Postgres, constructed from config.database_url" do
      fake_introspector = instance_double(SchemaReaper::Introspect::Postgres, call: fake_schema)
      allow(SchemaReaper::Introspect::Postgres).to receive(:new).and_return(fake_introspector)
      cfg = SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.merge("database_url" => "postgres:///whatever"))

      described_class.new(config: cfg, root: root).run

      expect(SchemaReaper::Introspect::Postgres).to have_received(:new).with("postgres:///whatever")
      expect(fake_introspector).to have_received(:call)
    end

    it "falls back to Runtime::Report.load, given config.runtime_log" do
      Dir.mktmpdir do |dir|
        log_path = File.join(dir, "runtime.jsonl")
        File.write(log_path, %({"key":"users.email","at":"2026-01-01T00:00:00Z"}\n))
        cfg = SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.merge("runtime_log" => log_path))

        findings = described_class.new(config: cfg, root: root, introspector: introspector).run

        # email is genuinely read per the runtime log, so it must not be
        # flagged dead even though config here has gem_awareness disabled.
        dead_columns = findings.select { |f| f.type == :dead_column }.map(&:column)
        expect(dead_columns).not_to include("email")
      end
    end

    it "falls back to real GemAwareness lookups when gem_awareness is enabled" do
      cfg = SchemaReaper::Config.new(
        SchemaReaper::Config::DEFAULTS.merge("scan_paths" => %w[app], "view_globs" => [])
      )
      allow(SchemaReaper::GemAwareness).to receive(:installed_gems).and_return(%w[devise])

      findings = described_class.new(
        config: cfg, root: root, introspector: introspector, runtime: SchemaReaper::Runtime::Report.empty
      ).run

      expect(SchemaReaper::GemAwareness).to have_received(:installed_gems).at_least(:once)
      # devise reserves `uid` on any table -- "abandoned_flag" is unrelated
      # to devise, so it's still correctly flagged even with gem awareness on.
      expect(findings.map(&:column)).to include("abandoned_flag")
    end
  end

  it "warns when the database has no usable query history for the unused-index analyzer" do
    table = fake_table("users", row_count: 20, indexes: [{ name: "idx_email", columns: %w[email] }],
                                columns: [{ name: "id" }, { name: "email" }])
    sparse_introspector = double(call: fake_schema(table, index_scan_total: 0))

    console = instance_double(SchemaReaper::Reporters::Console, notice: nil)
    allow(SchemaReaper::Reporters::Console).to receive(:new).and_return(console)

    described_class.new(config: config, root: root, introspector: sparse_introspector,
                        runtime: SchemaReaper::Runtime::Report.empty).run

    expect(console).to have_received(:notice).with(/unused_index skipped/)
  end

  it "loads plugin files listed under require:, relative to root" do
    cfg = SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.merge(
                                     "gem_awareness" => false, "require" => ["plugin_marker.rb"]
                                   ))

    described_class.new(config: cfg, root: root, introspector: introspector, runtime: SchemaReaper::Runtime::Report.empty)

    expect(Object.const_get(:SCHEMA_REAPER_PLUGIN_LOADED)).to be true
  end
end
