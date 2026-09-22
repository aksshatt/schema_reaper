# frozen_string_literal: true

RSpec.describe SchemaReaper::Finding do
  def finding(reclaimable_bytes:)
    described_class.new(
      type: :dead_column, table: "users", column: "x", severity: :high,
      confidence: 0.9, bytes_per_row: 8, reclaimable_bytes: reclaimable_bytes,
      evidence: ["nothing references it"], suggested_fix: "drop it"
    )
  end

  describe "#to_h" do
    it "keeps reclaimable_bytes nil, not 0, when the row count is unknown" do
      hash = finding(reclaimable_bytes: nil).to_h
      expect(hash[:reclaimable_bytes]).to be_nil
      expect(hash[:reclaim_known]).to be false
    end

    it "reports a genuinely zero reclaim as 0 with reclaim_known true" do
      hash = finding(reclaimable_bytes: 0).to_h
      expect(hash[:reclaimable_bytes]).to eq(0)
      expect(hash[:reclaim_known]).to be true
    end

    it "includes the id alongside the struct's own fields" do
      hash = finding(reclaimable_bytes: 8000).to_h
      expect(hash[:id]).to eq("dead_column/users/x")
      expect(hash[:reclaimable_bytes]).to eq(8000)
    end
  end
end
