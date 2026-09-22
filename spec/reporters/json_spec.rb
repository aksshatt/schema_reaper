# frozen_string_literal: true

require "stringio"
require "json"

RSpec.describe SchemaReaper::Reporters::Json do
  def finding(**over)
    SchemaReaper::Finding.new(
      { type: :dead_column, table: "users", column: "legacy", index: nil, severity: :medium,
        confidence: 0.6, bytes_per_row: 8, reclaimable_bytes: 8000,
        evidence: ["nothing references it"], suggested_fix: "drop it" }.merge(over)
    )
  end

  describe "#payload" do
    it "includes the gem version, a timestamp, and per-finding data" do
      payload = described_class.new([finding]).payload

      expect(payload[:version]).to eq(SchemaReaper::VERSION)
      expect(payload[:count]).to eq(1)
      expect(payload[:generated_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      expect(payload[:findings].first[:table]).to eq("users")
      expect(payload[:findings].first[:column]).to eq("legacy")
    end

    it "sums reclaimable_bytes across findings for the top-level total" do
      payload = described_class.new([finding(reclaimable_bytes: 1000), finding(reclaimable_bytes: 2000)]).payload
      expect(payload[:reclaimable_bytes]).to eq(3000)
    end

    it "treats an unmeasured finding as 0 in the top-level sum, but keeps it null per-finding" do
      payload = described_class.new([finding(reclaimable_bytes: nil)]).payload

      expect(payload[:reclaimable_bytes]).to eq(0)
      expect(payload[:findings].first[:reclaimable_bytes]).to be_nil
      expect(payload[:findings].first[:reclaim_known]).to be false
    end

    it "is empty but well-formed for a clean scan" do
      payload = described_class.new([]).payload
      expect(payload[:count]).to eq(0)
      expect(payload[:reclaimable_bytes]).to eq(0)
      expect(payload[:findings]).to eq([])
    end
  end

  describe "#render" do
    it "writes valid, pretty-printed JSON to the given io" do
      io = StringIO.new
      described_class.new([finding], io: io).render

      parsed = JSON.parse(io.string)
      expect(parsed["count"]).to eq(1)
      expect(parsed["findings"].first["table"]).to eq("users")
      expect(io.string).to include("\n  ") # pretty-printed, not a single line
    end
  end
end
