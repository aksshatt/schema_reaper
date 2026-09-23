# frozen_string_literal: true

RSpec.describe SchemaReaper::Analyzers::DeadColumn do
  let(:schema) do
    fake_schema(
      fake_table("users", row_count: 1000, foreign_keys: %w[org_id], columns: [
                   { name: "id" },
                   { name: "email", type: "character varying" },
                   { name: "legacy_ssn_hash", type: "character varying", null: true },
                   { name: "org_id" },
                   { name: "created_at" }
                 ])
    )
  end

  def findings(used:, runtime: nil, gem_columns: {}, config: nil)
    ctx = context_for(schema: schema, used: used, runtime: runtime, gem_columns: gem_columns, config: config)
    described_class.new(ctx).call
  end

  it "flags a column no token references" do
    result = findings(used: %w[email id])
    expect(result.map(&:column)).to eq(["legacy_ssn_hash"])
  end

  it "keeps pk, timestamps, fks and used columns" do
    expect(findings(used: %w[email legacy_ssn_hash])).to be_empty
  end

  it "keeps gem-reserved columns" do
    gem_cols = { "users" => Set["legacy_ssn_hash"] }
    expect(findings(used: %w[email], gem_columns: gem_cols)).to be_empty
  end

  it "caps confidence at 0.6 for static-only signal" do
    expect(findings(used: %w[email]).first.confidence).to be <= 0.6
  end

  it "raises confidence when runtime data confirms the column is unread" do
    rt = runtime_report(accessed: %w[users.email], observed_days: 30)
    expect(findings(used: %w[email], runtime: rt).first.confidence).to be > 0.6
  end

  describe "min_age_days" do
    let(:rt) { runtime_report(accessed: %w[users.email], observed_days: 20) }

    def config_with(days)
      SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.merge("min_age_days" => days))
    end

    it "trusts runtime data once it spans the default 14 days" do
      expect(findings(used: %w[email], runtime: rt).first.confidence).to be > 0.6
    end

    it "keeps the static cap until runtime data spans the configured minimum" do
      expect(findings(used: %w[email], runtime: rt, config: config_with(30)).first.confidence).to be <= 0.6
    end

    it "trusts shorter runtime data when the minimum is lowered" do
      short = runtime_report(accessed: %w[users.email], observed_days: 7)
      expect(findings(used: %w[email], runtime: short, config: config_with(7)).first.confidence).to be > 0.6
    end

    it "falls back to the default when a config has no min_age_days" do
      bare = SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.reject { |k, _| k == "min_age_days" })
      expect(findings(used: %w[email], runtime: rt, config: bare).first.confidence).to be > 0.6
    end
  end

  it "computes reclaimable bytes from the row count" do
    f = findings(used: %w[email]).first
    expect(f.reclaimable_bytes).to eq(f.bytes_per_row * 1000)
  end
end
