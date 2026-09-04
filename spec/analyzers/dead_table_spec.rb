# frozen_string_literal: true

RSpec.describe SchemaReaper::Analyzers::DeadTable do
  def findings(table_name, used:, row_count: 0)
    schema = fake_schema(
      fake_table(table_name, row_count: row_count, columns: [{ name: "id" }])
    )
    described_class.new(context_for(schema: schema, used: used)).call
  end

  it "flags a table nothing references" do
    expect(findings("legacy_imports", used: %w[users email]).map(&:table))
      .to eq(["legacy_imports"])
  end

  it "matches the table name itself" do
    expect(findings("orders", used: %w[orders])).to be_empty
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
end
