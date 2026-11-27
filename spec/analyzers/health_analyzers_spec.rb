# frozen_string_literal: true

RSpec.describe "health analyzers" do
  def findings(klass, schema, config: nil)
    klass.new(context_for(schema: schema, config: config)).call
  end

  def sequence(last_value:, max_value: 2_147_483_647, column_type: "integer", table: "events")
    SchemaReaper::Sequence.new(
      name: "#{table}_id_seq", table: table, column: "id", column_type: column_type,
      last_value: last_value, max_value: max_value
    )
  end

  describe SchemaReaper::Analyzers::SequenceExhaustion do
    def schema_with(*seqs)
      SchemaReaper::DatabaseSchema.new(tables: [], index_scan_total: nil, sequences: seqs)
    end

    it "stays quiet below half the column's range" do
      expect(findings(described_class, schema_with(sequence(last_value: 1_000_000)))).to be_empty
    end

    it "flags a sequence past half its range as medium, and past three quarters as high" do
      medium = findings(described_class, schema_with(sequence(last_value: 1_200_000_000))).first
      high = findings(described_class, schema_with(sequence(last_value: 2_000_000_000))).first

      expect(medium.severity).to eq(:medium)
      expect(high.severity).to eq(:high)
      expect(high.suggested_fix).to include("change_column :events, :id, :bigint")
      expect(high.evidence.first).to include("93.1%")
    end

    it "suggests raising the sequence, not the column, when the column is already bigint" do
      seq = sequence(last_value: 90, max_value: 100, column_type: "bigint")
      expect(findings(described_class, schema_with(seq)).first.suggested_fix).to include("ALTER SEQUENCE")
    end

    it "respects ignore.tables" do
      cfg = SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.merge("ignore" => { "tables" => ["events"] }))
      expect(findings(described_class, schema_with(sequence(last_value: 2_000_000_000)), config: cfg)).to be_empty
    end
  end

  describe SchemaReaper::Analyzers::DuplicateForeignKey do
    def table_with(*fks)
      table = fake_table("orders", columns: [{ name: "id" }, { name: "account_id" }])
      table.foreign_key_constraints = fks.map do |name, cols, ref|
        SchemaReaper::ForeignKey.new(name: name, columns: cols, references: ref)
      end
      table
    end

    it "reports every copy after the first of an identical constraint" do
      schema = fake_schema(table_with(
                             ["fk_rails_abc", %w[account_id], "accounts"],
                             ["orders_account_fk", %w[account_id], "accounts"]
                           ))
      result = findings(described_class, schema)

      expect(result.map(&:index)).to eq(["orders_account_fk"])
      expect(result.first.suggested_fix).to eq("remove_foreign_key :orders, name: :orders_account_fk")
    end

    it "does not treat constraints to different tables as duplicates" do
      schema = fake_schema(table_with(
                             ["fk_a", %w[account_id], "accounts"],
                             ["fk_b", %w[account_id], "legacy_accounts"]
                           ))
      expect(findings(described_class, schema)).to be_empty
    end
  end

  describe "ignore.columns across column analyzers" do
    let(:cfg) do
      SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.merge(
                                 "ignore" => { "tables" => [], "columns" => ["/^legacy_/"] }
                               ))
    end

    it "silences always_null_column, single_value_column and missing_fk_index" do
      schema = fake_schema(
        fake_table("users", row_count: 10_000, columns: [
                     { name: "id" },
                     { name: "legacy_note", null_fraction: 1.0 },
                     { name: "legacy_flag", distinct_values: 1 },
                     { name: "legacy_owner_id", null_fraction: 0.1 }
                   ])
      )

      [SchemaReaper::Analyzers::AlwaysNullColumn, SchemaReaper::Analyzers::SingleValueColumn,
       SchemaReaper::Analyzers::MissingFkIndex].each do |klass|
        expect(findings(klass, schema, config: cfg)).to be_empty, "#{klass.type} ignored the list"
      end
    end
  end

  describe SchemaReaper::Analyzers::DeadTable do
    it "matches a non-public table by its bare name and model" do
      schema = fake_schema(fake_table("billing.invoices", columns: [{ name: "id" }], row_count: 0))
      ctx = context_for(schema: schema, used: %w[invoice])

      expect(described_class.new(ctx).call).to be_empty
    end

    it "treats raw-SQL runtime access (table.*) as use" do
      schema = fake_schema(fake_table("audits", columns: [{ name: "id" }], row_count: 0))
      ctx = context_for(schema: schema, runtime: runtime_report(accessed: ["audits.*"], observed_days: 30))

      expect(described_class.new(ctx).call).to be_empty
    end
  end
end
