# frozen_string_literal: true

require "stringio"

RSpec.describe SchemaReaper::Reporters::Table do
  def finding(**over)
    SchemaReaper::Finding.new(
      { type: :dead_column, table: "users", column: "legacy", index: nil,
        severity: :high, confidence: 0.85, bytes_per_row: 8, reclaimable_bytes: 8000,
        evidence: ["nothing references it", "table holds ~1000 row(s)"],
        suggested_fix: "remove_column :users, :legacy" }.merge(over)
    )
  end

  def render(list, **opts)
    io = StringIO.new
    described_class.new(list, io: io, color: false, **opts).render
    io.string
  end

  it "shows a clean-state line when there are no findings" do
    expect(render([])).to include("no findings")
  end

  it "prints a summary header with count and reclaimable total" do
    out = render([finding])
    expect(out).to include("schema_reaper", "1 finding", "7.8 KB reclaimable")
  end

  it "groups findings under their table name" do
    out = render([finding(table: "users"), finding(table: "orders", column: "x")])
    expect(out).to match(/^  users$/)
    expect(out).to match(/^  orders$/)
  end

  it "renders a confidence bar, percentage, severity and the fix arrow" do
    out = render([finding(confidence: 0.6)])
    expect(out).to include("███░░", "60%", "high", "→ remove_column :users, :legacy")
  end

  it "joins evidence with a middot" do
    expect(render([finding])).to include("nothing references it · table holds ~1000 row(s)")
  end

  it "emits no ANSI escapes when colour is disabled" do
    expect(render([finding])).not_to include("\e[")
  end

  it "shows a severity tally and a per-type breakdown in the footer" do
    out = render([finding(severity: :high), finding(severity: :low, column: "b", type: :unused_index)])
    expect(out).to include("high 1", "low 1")
    expect(out).to include("dead_column 1", "unused_index 1")
  end

  it "omits the trailing byte column on a finding that reclaims nothing" do
    out = render([finding(reclaimable_bytes: 0, bytes_per_row: 0)])
    finding_line = out.lines.find { |l| l.include?("dead_column") }
    expect(finding_line).not_to match(/B\s*$/)
  end
end

RSpec.describe SchemaReaper::Reporters::Ansi do
  it "is disabled for a non-tty io" do
    expect(described_class.new(io: StringIO.new).on?).to be(false)
  end

  it "honours an explicit enable flag and wraps text in codes" do
    a = described_class.new(io: StringIO.new, enabled: true)
    expect(a.paint("x", :bold)).to eq("\e[1mx\e[0m")
  end

  it "returns text unchanged when disabled" do
    a = described_class.new(io: StringIO.new, enabled: false)
    expect(a.paint("x", :bold, :red)).to eq("x")
  end

  it "builds a five-cell confidence bar" do
    a = described_class.new(io: StringIO.new, enabled: false)
    expect(a.confidence_bar(0.6, :low)).to eq("███░░")
    expect(a.confidence_bar(1.0, :high)).to eq("█████")
    expect(a.confidence_bar(0.0, :low)).to eq("░░░░░")
  end
end
