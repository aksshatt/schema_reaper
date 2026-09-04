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

  def findings(used:, runtime: nil, gem_columns: {})
    ctx = context_for(schema: schema, used: used, runtime: runtime, gem_columns: gem_columns)
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

  it "computes reclaimable bytes from the row count" do
    f = findings(used: %w[email]).first
    expect(f.reclaimable_bytes).to eq(f.bytes_per_row * 1000)
  end
end
