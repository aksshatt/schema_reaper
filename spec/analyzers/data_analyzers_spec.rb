# frozen_string_literal: true

RSpec.describe "data-shape analyzers" do
  def findings(klass, schema, used: [])
    klass.new(context_for(schema: schema, used: used)).call
  end

  describe SchemaReaper::Analyzers::AlwaysNullColumn do
    it "flags a column that is NULL in every row" do
      schema = fake_schema(
        fake_table("users", row_count: 5000, columns: [
                     { name: "id" },
                     { name: "middle_name", null: true, null_fraction: 1.0 },
                     { name: "email", null: false, null_fraction: 0.0 }
                   ])
      )
      expect(findings(described_class, schema).map(&:column)).to eq(["middle_name"])
    end

    it "does nothing on an empty table" do
      schema = fake_schema(
        fake_table("users", row_count: 0, columns: [{ name: "x", null_fraction: 1.0 }])
      )
      expect(findings(described_class, schema)).to be_empty
    end
  end

  describe SchemaReaper::Analyzers::SingleValueColumn do
    it "flags a column with one distinct value on a large table" do
      schema = fake_schema(
        fake_table("accounts", row_count: 10_000, columns: [
                     { name: "id" },
                     { name: "region", distinct_values: 1 },
                     { name: "plan", distinct_values: 4 }
                   ])
      )
      expect(findings(described_class, schema).map(&:column)).to eq(["region"])
    end

    it "stays quiet on small tables" do
      schema = fake_schema(
        fake_table("accounts", row_count: 12, columns: [{ name: "region", distinct_values: 1 }])
      )
      expect(findings(described_class, schema)).to be_empty
    end
  end

  describe SchemaReaper::Analyzers::DeadTable do
    it "flags a zero-row table nothing references" do
      schema = fake_schema(
        fake_table("legacy_imports", row_count: 0, columns: [{ name: "id" }, { name: "blob" }])
      )
      expect(findings(described_class, schema).map(&:table)).to eq(["legacy_imports"])
    end

    it "keeps a table referenced by its model name" do
      schema = fake_schema(
        fake_table("widgets", row_count: 0, columns: [{ name: "id" }])
      )
      expect(findings(described_class, schema, used: %w[widget])).to be_empty
    end
  end
end
