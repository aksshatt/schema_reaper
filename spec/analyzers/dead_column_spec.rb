# frozen_string_literal: true

RSpec.describe SchemaReaper::Analyzers::DeadColumn do
  let(:config) { SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.dup) }

  let(:schema) do
    fake_schema(
      fake_table("users", columns: [
                   { name: "id" },
                   { name: "email", type: "character varying" },
                   { name: "legacy_ssn_hash", type: "character varying", null: true },
                   { name: "org_id" },
                   { name: "created_at" }
                 ], foreign_keys: %w[org_id])
    )
  end

  def findings(used)
    ctx = SchemaReaper::Analyzers::Context.new(schema: schema, used_tokens: used, config: config)
    described_class.new(ctx).call
  end

  it "flags a column no token references" do
    result = findings(Set["email", "id"])
    expect(result.map(&:column)).to eq(["legacy_ssn_hash"])
  end

  it "keeps pk, timestamps, fks and used columns" do
    result = findings(Set["email", "legacy_ssn_hash"])
    expect(result).to be_empty
  end

  it "caps confidence for static-only signal" do
    result = findings(Set["email"])
    expect(result.first.confidence).to be <= described_class::MAX_STATIC_CONFIDENCE
  end

  it "carries a staged-removal fix" do
    result = findings(Set["email"])
    expect(result.first.suggested_fix).to include("ignored_columns")
  end
end
