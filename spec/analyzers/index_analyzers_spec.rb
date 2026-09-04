# frozen_string_literal: true

RSpec.describe "index analyzers" do
  def findings(klass, schema, used: [])
    klass.new(context_for(schema: schema, used: used)).call
  end

  describe SchemaReaper::Analyzers::UnusedIndex do
    it "flags a non-unique index with zero scans" do
      schema = fake_schema(
        fake_table("orders", row_count: 10, columns: [{ name: "id" }, { name: "state" }],
                             indexes: [
                               { name: "idx_orders_on_state", columns: %w[state], scans: 0 },
                               { name: "idx_orders_hot", columns: %w[created_at], scans: 4200 }
                             ])
      )
      result = findings(described_class, schema)
      expect(result.map(&:index)).to eq(["idx_orders_on_state"])
    end

    it "ignores indexes when no scan stats are present" do
      schema = fake_schema(
        fake_table("orders", columns: [{ name: "id" }],
                             indexes: [{ name: "idx", columns: %w[x], scans: nil }])
      )
      expect(findings(described_class, schema)).to be_empty
    end
  end

  describe SchemaReaper::Analyzers::DuplicateIndex do
    it "flags an index that is a prefix of a wider one" do
      schema = fake_schema(
        fake_table("events", columns: [{ name: "id" }],
                             indexes: [
                               { name: "idx_a", columns: %w[account_id] },
                               { name: "idx_ab", columns: %w[account_id created_at] }
                             ])
      )
      expect(findings(described_class, schema).map(&:index)).to eq(["idx_a"])
    end

    it "does not flag an index matching a non-leading column of a wider one" do
      schema = fake_schema(
        fake_table("events", columns: [{ name: "id" }],
                             indexes: [
                               { name: "idx_created_at", columns: %w[created_at] },
                               { name: "idx_account_created", columns: %w[account_id created_at] }
                             ])
      )
      expect(findings(described_class, schema)).to be_empty
    end
  end

  describe SchemaReaper::Analyzers::MissingFkIndex do
    it "flags an unindexed *_id column" do
      schema = fake_schema(
        fake_table("comments", foreign_keys: %w[post_id],
                               columns: [{ name: "id" }, { name: "post_id" }, { name: "user_id" }],
                               indexes: [{ name: "idx_comments_on_post_id", columns: %w[post_id] }])
      )
      expect(findings(described_class, schema).map(&:column)).to eq(["user_id"])
    end
  end
end
