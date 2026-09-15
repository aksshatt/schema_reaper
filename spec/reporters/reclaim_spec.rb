# frozen_string_literal: true

RSpec.describe SchemaReaper::Reporters::Reclaim do
  def finding(**over)
    SchemaReaper::Finding.new(
      { type: :dead_column, table: "t", column: "c", severity: :medium,
        confidence: 0.6, bytes_per_row: 8, reclaimable_bytes: 8000,
        evidence: ["x"], suggested_fix: "y" }.merge(over)
    )
  end

  describe ".summary" do
    it "states the total when it is known and positive" do
      expect(described_class.summary([finding])).to eq("~7.8 KB reclaimable")
    end

    it "says the estimate is unavailable when a row count is unknown" do
      list = [finding(reclaimable_bytes: nil, bytes_per_row: 8)]
      expect(described_class.summary(list)).to include("unavailable", "ANALYZE")
    end

    it "says nothing when every estimate is known and zero" do
      list = [finding(reclaimable_bytes: 0, bytes_per_row: 8)]
      expect(described_class.summary(list)).to be_nil
    end

    it "does not call a finding unmeasured when it never reclaims bytes" do
      # missing_fk_index / duplicate_index: bytes_per_row 0, so an unknown row
      # count does not change the answer -- it is always 0.
      list = [finding(type: :missing_fk_index, bytes_per_row: 0, reclaimable_bytes: nil)]
      expect(described_class.summary(list)).to be_nil
    end
  end

  describe ".cell" do
    it "renders the human size for a measured finding" do
      expect(described_class.cell(finding)).to eq("7.8 KB")
    end

    it "says unknown for an unmeasured finding" do
      f = finding(reclaimable_bytes: nil, bytes_per_row: 8)
      expect(described_class.cell(f)).to eq("unknown")
    end

    it "renders 0.0 B rather than unknown for a finding that never reclaims bytes" do
      f = finding(type: :missing_fk_index, bytes_per_row: 0, reclaimable_bytes: nil)
      expect(described_class.cell(f)).to eq("0.0 B")
    end
  end
end
