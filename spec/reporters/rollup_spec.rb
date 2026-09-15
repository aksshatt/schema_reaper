# frozen_string_literal: true

RSpec.describe SchemaReaper::Reporters::Rollup do
  def fk_finding(table, column, index: nil, evidence: nil, fix: nil)
    SchemaReaper::Finding.new(
      type: :missing_fk_index, table: table, column: column, index: index,
      severity: :medium, confidence: 0.9, bytes_per_row: 0, reclaimable_bytes: 0,
      evidence: [evidence || "#{column} has no covering index"],
      suggested_fix: fix || "add_index :#{table}, :#{column}"
    )
  end

  it "rolls up findings that differ only in the names they mention" do
    findings = %w[a b c d].map { |t| fk_finding("#{t}_table", "#{t}_id") }
    rolled, itemised = described_class.partition(findings)

    expect(rolled.size).to eq(1)
    expect(rolled.first.last.size).to eq(4)
    expect(itemised).to be_empty
  end

  it "leaves a group below the threshold spelled out" do
    findings = %w[a b c].map { |t| fk_finding("#{t}_table", "#{t}_id") }
    rolled, itemised = described_class.partition(findings)

    expect(rolled).to be_empty
    expect(itemised.size).to eq(3)
  end

  it "keeps the fix readable as a template" do
    findings = %w[a b c d].map { |t| fk_finding("#{t}_table", "#{t}_id") }
    _type, _evidence, fix = described_class.partition(findings).first.first.first

    expect(fix).to eq("add_index :<table>, :<column>")
  end

  it "does not merge findings whose names differ only past a suffix" do
    # index_x_on_y must not be masked out of index_x_on_y_and_state, or two
    # findings about different covering indexes look identical.
    findings = %w[a b c d].map do |t|
      fk_finding("#{t}_table", "#{t}_id", index: "index_#{t}_on_id",
                                          evidence: "index_#{t}_on_id is a prefix of index_#{t}_on_id_and_state_#{t}")
    end
    rolled, itemised = described_class.partition(findings)

    expect(rolled).to be_empty
    expect(itemised.size).to eq(4)
  end

  it "separates groups whose evidence genuinely differs" do
    declared = %w[a b c d].map { |t| fk_finding("#{t}_t", "#{t}_id", evidence: "#{t}_id: declared constraint") }
    guessed  = %w[e f g h].map { |t| fk_finding("#{t}_t", "#{t}_id", evidence: "#{t}_id: matched by name") }
    rolled, = described_class.partition(declared + guessed)

    expect(rolled.size).to eq(2)
    expect(rolled.map { |_key, group| group.size }).to eq([4, 4])
  end
end
