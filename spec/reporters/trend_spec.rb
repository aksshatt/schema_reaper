# frozen_string_literal: true

require "stringio"

RSpec.describe SchemaReaper::Reporters::Trend do
  def render(data)
    io = StringIO.new
    described_class.new(data, io: io, color: false).render
    io.string
  end

  it "explains the empty state" do
    expect(render(snapshots: 0)).to include("no snapshots yet")
  end

  it "tells a first-run user to come back later" do
    out = render(snapshots: 1, first_at: "2026-09-09T00:00:00Z", last_at: "2026-09-09T00:00:00Z")
    expect(out).to include("first snapshot recorded", "Run this again later")
  end

  it "shows signed deltas, new/resolved lists and short dates" do
    out = render(
      snapshots: 3,
      first_at: "2026-08-01T10:00:00Z", last_at: "2026-09-09T10:00:00Z",
      latest_count: 7, latest_bytes: 192_000,
      count_change_total: -5, count_change_last: -2,
      newly_introduced: ["dead_column/users/x"],
      resolved_since_prev: ["unused_index/orders/y"],
      bytes_change_total: -1_100_000
    )

    expect(out).to include("3 snapshots")
    expect(out).to include("findings", "7", "-5 since first run · -2 since last")
    expect(out).to include("reclaimable", "-1.0 MB since first run")
    expect(out).to include("new since last run:", "- dead_column/users/x")
    expect(out).to include("resolved since last run:", "- unused_index/orders/y")
    expect(out).to include("2026-08-01", "2026-09-09")
    expect(out).not_to include(":snapshots=>") # no raw hash dump
  end

  it "shows an unsigned zero byte delta, not -0.0 B" do
    out = render(
      snapshots: 2,
      first_at: "2026-08-01T10:00:00Z", last_at: "2026-09-09T10:00:00Z",
      latest_count: 7, latest_bytes: 192_000,
      count_change_total: 0, count_change_last: 0,
      bytes_change_total: 0
    )

    expect(out).to include("+0.0 B since first run")
    expect(out).not_to include("-0.0 B")
  end
end

RSpec.describe SchemaReaper::Reporters::Console do
  def streams
    [StringIO.new, StringIO.new]
  end

  it "prints an ok line to stdout and a problem block to stderr" do
    out, err = streams
    c = described_class.new(out: out, err: err, color: false)
    c.ok("done")
    c.problem("2 new findings", items: %w[a/b c/d])

    expect(out.string).to include("✓ done")
    expect(err.string).to include("✗ 2 new findings", "- a/b", "- c/d")
    expect(out.string).not_to include("✗")
  end

  it "aligns label/value rows" do
    out, err = streams
    described_class.new(out: out, err: err, color: false).row("findings", 7, "-1 since last")
    expect(out.string).to match(/  findings\s+7  \(-1 since last\)/)
  end
end
