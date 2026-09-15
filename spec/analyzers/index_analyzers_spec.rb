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

    it "reports nothing when the database has no query history" do
      schema = fake_schema(
        fake_table("orders", row_count: 10, columns: [{ name: "id" }],
                             indexes: [
                               { name: "idx_a", columns: %w[a], scans: 0 },
                               { name: "idx_b", columns: %w[b], scans: 0 }
                             ]),
        index_scan_total: 1
      )
      expect(findings(described_class, schema)).to be_empty
    end

    it "still reports once the database has served queries" do
      schema = fake_schema(
        fake_table("orders", row_count: 10, columns: [{ name: "id" }],
                             indexes: [
                               { name: "idx_cold", columns: %w[a], scans: 0 },
                               { name: "idx_hot", columns: %w[b], scans: 9000 }
                             ]),
        index_scan_total: 9000
      )
      expect(findings(described_class, schema).map(&:index)).to eq(["idx_cold"])
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

    it "accepts a composite (type, id) index for a polymorphic association" do
      schema = fake_schema(
        fake_table("comments",
                   columns: [{ name: "id" }, { name: "commentable_type" }, { name: "commentable_id" }],
                   indexes: [{ name: "idx_on_commentable", columns: %w[commentable_type commentable_id] }])
      )
      expect(findings(described_class, schema)).to be_empty
    end

    it "accepts a composite index with trailing columns after the pair" do
      schema = fake_schema(
        fake_table("audits",
                   columns: [{ name: "id" }, { name: "auditable_type" }, { name: "auditable_id" },
                             { name: "version" }],
                   indexes: [{ name: "auditable_index",
                               columns: %w[auditable_type auditable_id version] }])
      )
      expect(findings(described_class, schema)).to be_empty
    end

    it "suggests the composite index when a polymorphic association is unindexed" do
      schema = fake_schema(
        fake_table("comments",
                   columns: [{ name: "id" }, { name: "commentable_type" }, { name: "commentable_id" }])
      )
      result = findings(described_class, schema)

      expect(result.map(&:column)).to eq(["commentable_id"])
      expect(result.first.suggested_fix).to eq("add_index :comments, %i[commentable_type commentable_id]")
    end

    it "does not accept an index on the id alone as covering a polymorphic pair" do
      schema = fake_schema(
        fake_table("comments",
                   columns: [{ name: "id" }, { name: "commentable_type" }, { name: "commentable_id" }],
                   indexes: [{ name: "idx_type_only", columns: %w[commentable_type] }])
      )
      expect(findings(described_class, schema).map(&:column)).to eq(["commentable_id"])
    end

    it "does not advise indexing a foreign-key column that is NULL in every row" do
      schema = fake_schema(
        fake_table("categories", row_count: 4000, columns: [
                     { name: "id" },
                     { name: "parent_id", null: true, null_fraction: 1.0 }
                   ])
      )
      expect(findings(described_class, schema)).to be_empty
    end

    it "still flags an unindexed foreign key that holds data" do
      schema = fake_schema(
        fake_table("categories", row_count: 4000, columns: [
                     { name: "id" },
                     { name: "parent_id", null: true, null_fraction: 0.2 }
                   ])
      )
      expect(findings(described_class, schema).map(&:column)).to eq(["parent_id"])
    end

    describe "confidence tiers" do
      def tier(col, tables)
        schema = fake_schema(*tables)
        findings(SchemaReaper::Analyzers::MissingFkIndex, schema).find { |f| f.column == col }
      end

      it "is highest for a declared foreign key constraint" do
        f = tier("post_id", [
                   fake_table("comments", foreign_keys: %w[post_id],
                                          columns: [{ name: "id" }, { name: "post_id" }]),
                   fake_table("posts", columns: [{ name: "id" }])
                 ])
        expect(f.confidence).to eq(described_class::CONSTRAINT_CONFIDENCE)
        expect(f.evidence.first).to include("declared foreign key constraint")
      end

      it "is middling for a *_id name with a table it plausibly references" do
        f = tier("account_id", [
                   fake_table("events", columns: [{ name: "id" }, { name: "account_id" }]),
                   fake_table("accounts", columns: [{ name: "id" }])
                 ])
        expect(f.confidence).to eq(described_class::REFERENT_CONFIDENCE)
        expect(f.evidence.first).to include("named like a reference to `accounts`")
      end

      it "is lowest for a *_id name with nothing to reference" do
        f = tier("voter_id", [
                   fake_table("profiles", columns: [{ name: "id" }, { name: "voter_id" }])
                 ])
        expect(f.confidence).to eq(described_class::NAME_ONLY_CONFIDENCE)
        expect(f.severity).to eq(:low)
        expect(f.evidence.first).to include("matched on the _id suffix alone")
      end

      it "pluralises a -y stem when looking for the referent" do
        f = tier("company_id", [
                   fake_table("contacts", columns: [{ name: "id" }, { name: "company_id" }]),
                   fake_table("companies", columns: [{ name: "id" }])
                 ])
        expect(f.confidence).to eq(described_class::REFERENT_CONFIDENCE)
      end

      it "keeps a declared constraint at full confidence with no referent table" do
        f = tier("manager_id", [
                   fake_table("staff", foreign_keys: %w[manager_id],
                                       columns: [{ name: "id" }, { name: "manager_id" }])
                 ])
        expect(f.confidence).to eq(described_class::CONSTRAINT_CONFIDENCE)
      end
    end
  end
end
