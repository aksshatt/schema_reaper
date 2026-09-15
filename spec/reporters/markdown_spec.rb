# frozen_string_literal: true

require "stringio"

RSpec.describe SchemaReaper::Reporters::Markdown do
  def finding(**over)
    SchemaReaper::Finding.new(
      { type: :dead_column, table: "users", column: "legacy", severity: :high,
        confidence: 0.85, bytes_per_row: 8, reclaimable_bytes: 8000,
        evidence: ["nothing references it"], suggested_fix: "remove_column :users, :legacy" }.merge(over)
    )
  end

  def render(list)
    io = StringIO.new
    described_class.new(list, io: io).render
    io.string
  end

  it "shows the clean-state message when there are no findings" do
    expect(render([])).to include("No findings")
  end

  it "states the reclaim total when it is known" do
    expect(render([finding])).to include("1 finding(s). **~7.8 KB reclaimable.**")
  end

  it "says the estimate is unavailable when a row count is unknown" do
    out = render([finding(reclaimable_bytes: nil, bytes_per_row: 8)])
    expect(out).to include("reclaim estimate unavailable", "ANALYZE")
  end

  it "adds no reclaim clause when every estimate is known and zero" do
    out = render([finding(reclaimable_bytes: 0, bytes_per_row: 8)])
    expect(out).to include("1 finding(s).\n")
    expect(out).not_to include("reclaimable", "ANALYZE", "unavailable")
  end

  it "marks an unmeasured row's cell as unknown rather than 0.0 B" do
    out = render([finding(reclaimable_bytes: nil, bytes_per_row: 8)])
    expect(out).to include("| unknown |")
  end

  it "prints 0.0 B for a row that never reclaims bytes, even with no row count" do
    out = render([finding(type: :missing_fk_index, bytes_per_row: 0, reclaimable_bytes: nil,
                          evidence: ["no covering index"], suggested_fix: "add_index :t, :c")])
    expect(out).to include("| 0.0 B |")
  end

  it "renders one row per finding, sorted by confidence" do
    out = render([finding(confidence: 0.5, table: "a"), finding(confidence: 0.9, table: "b")])
    rows = out.lines.grep(/^\| /).drop(1)
    expect(rows.first).to include("90%")
    expect(rows.last).to include("50%")
  end
end
