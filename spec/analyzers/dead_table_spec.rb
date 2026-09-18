# frozen_string_literal: true

RSpec.describe SchemaReaper::Analyzers::DeadTable do
  def findings(table_name, used:, row_count: 0, gem_owned_tables: Set.new)
    schema = fake_schema(
      fake_table(table_name, row_count: row_count, columns: [{ name: "id" }])
    )
    described_class.new(context_for(schema: schema, used: used, gem_owned_tables: gem_owned_tables)).call
  end

  it "flags a table nothing references" do
    expect(findings("legacy_imports", used: %w[users email]).map(&:table))
      .to eq(["legacy_imports"])
  end

  it "matches the table name itself" do
    expect(findings("orders", used: %w[orders])).to be_empty
  end

  context "when the row count is unknown (table never analysed)" do
    subject(:finding) { findings("legacy_imports", used: [], row_count: nil).first }

    it "reports it at medium confidence, not the 0.4 non-empty level" do
      expect(finding.confidence).to eq(0.5)
    end

    it "says the count is unknown and suggests ANALYZE" do
      expect(finding.evidence).to include(a_string_matching(/row count unknown.*ANALYZE/))
    end

    it "does not produce a negative reclaimable estimate" do
      expect(finding.reclaimable_bytes).to be >= 0
    end
  end

  describe "singular and model forms" do
    it "matches an -ies table against its model constant" do
      expect(findings("crm_activities", used: %w[crmactivity])).to be_empty
    end

    it "matches an -ies table against its singular name" do
      expect(findings("activities", used: %w[activity])).to be_empty
    end

    it "matches an -sses table against its singular name" do
      expect(findings("addresses", used: %w[address])).to be_empty
    end

    it "matches an -xes table against its singular name" do
      expect(findings("boxes", used: %w[box])).to be_empty
    end

    it "still matches a plain -s table against its singular name" do
      expect(findings("employees", used: %w[employee])).to be_empty
    end
  end

  describe "names buried inside longer identifiers" do
    it "matches a route helper that embeds the table name" do
      expect(findings("crm_activities", used: %w[admin_crm_activities_path])).to be_empty
    end

    it "matches when the name is the leading segment" do
      expect(findings("orders", used: %w[orders_controller])).to be_empty
    end

    it "does not match a name that is only a substring of one segment" do
      expect(findings("logs", used: %w[catalogs]).map(&:table)).to eq(["logs"])
    end
  end

  describe "tables a gem owns outright" do
    it "does not flag a table the static scanner would otherwise call dead" do
      # No app code ever mentions active_admin_comments directly -- ActiveAdmin's
      # own internal classes read and write it, which the static scanner cannot
      # see at all.
      expect(findings("active_admin_comments", used: [], gem_owned_tables: Set["active_admin_comments"]))
        .to be_empty
    end

    it "still flags an app table with the same shape of reference gap" do
      expect(findings("legacy_imports", used: [], gem_owned_tables: Set["active_admin_comments"]).map(&:table))
        .to eq(["legacy_imports"])
    end
  end
end
