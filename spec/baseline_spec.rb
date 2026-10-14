# frozen_string_literal: true

require "tmpdir"
require "json"

RSpec.describe SchemaReaper::Baseline do
  def finding(column)
    SchemaReaper::Finding.new(type: :dead_column, table: "users", column: column, severity: :low,
                              confidence: 0.5, bytes_per_row: 0, evidence: [], suggested_fix: "")
  end

  around { |ex| Dir.mktmpdir { |dir| @path = File.join(dir, "baseline.json") and ex.run } }

  it "reads the 2.0 ids-only format" do
    File.write(@path, JSON.generate("ids" => ["dead_column/users/a"]))
    expect(described_class.new(@path).new_among([finding("a"), finding("b")]).map(&:column)).to eq(["b"])
  end

  it "stores reason and expiry, keeping them for entries already present" do
    described_class.new(@path).write([finding("a")], reason: "ETL reads it", expires_on: Date.new(2030, 1, 1))
    described_class.new(@path).write([finding("a"), finding("b")], reason: "other")

    entries = described_class.new(@path).entries.to_h { |e| [e.id, e] }
    expect(entries["dead_column/users/a"].reason).to eq("ETL reads it")
    expect(entries["dead_column/users/a"].expires_on).to eq(Date.new(2030, 1, 1))
    expect(entries["dead_column/users/b"].reason).to eq("other")
  end

  it "treats an expired entry as new again" do
    described_class.new(@path).write([finding("a")], expires_on: Date.today - 1)
    base = described_class.new(@path)

    expect(base.new_among([finding("a")]).size).to eq(1)
    expect(base.expired.map(&:id)).to eq(["dead_column/users/a"])
  end

  it "prunes resolved entries without accepting new findings" do
    described_class.new(@path).write([finding("a"), finding("b")])
    dropped = described_class.new(@path).prune([finding("b"), finding("c")])

    expect(dropped).to eq(["dead_column/users/a"])
    expect(described_class.new(@path).entries.map(&:id)).to eq(["dead_column/users/b"])
  end
end
