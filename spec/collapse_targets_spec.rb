# frozen_string_literal: true

RSpec.describe "Runner target collapsing" do
  # fixtures/app/models/user.rb defines `class User`, so the `users` table is
  # referenced and dead_table does not swallow the per-column findings.
  let(:root) { File.expand_path("fixtures", __dir__) }
  let(:config) do
    SchemaReaper::Config.new(
      SchemaReaper::Config::DEFAULTS.merge(
        "scan_paths" => %w[app], "view_globs" => [], "gem_awareness" => false
      )
    )
  end

  # users.legacy_token: dead (no ref) AND always-NULL -> two analyzers, one column.
  # users.name index: unused AND a duplicate prefix -> two analyzers, one index.
  let(:schema) do
    fake_schema(
      fake_table("users", row_count: 5000, primary_key: "id", columns: [
                   { name: "id" },
                   { name: "email", null: false },
                   { name: "name", null: true },
                   { name: "legacy_token", null: true, bytes: 16, null_fraction: 1.0 }
                 ], indexes: [
                   { name: "idx_users_on_name", columns: %w[name], scans: 0 },
                   { name: "idx_users_on_name_and_email", columns: %w[name email], scans: 500 }
                 ])
    )
  end

  let(:introspector) do
    Struct.new(:s) do
      def call
        s
      end
    end.new(schema)
  end

  subject(:findings) do
    SchemaReaper::Runner.new(
      config: config, root: root, introspector: introspector,
      runtime: SchemaReaper::Runtime::Report.empty
    ).run
  end

  it "reports each physical column at most once" do
    per_column = findings.select(&:column).reject(&:index).group_by { |f| [f.table, f.column] }
    expect(per_column.values.map(&:size)).to all(eq(1))
  end

  it "keeps the highest-confidence analyzer for a collapsed column" do
    token = findings.find { |f| f.column == "legacy_token" && f.index.nil? }
    expect(token.type).to eq(:always_null_column)          # 0.85 beats dead_column 0.5
    expect(token.evidence.last).to eq("also flagged by: dead_column")
  end

  it "reports each physical index at most once" do
    per_index = findings.select(&:index).group_by { |f| [f.table, f.index] }
    expect(per_index.values.map(&:size)).to all(eq(1))
  end

  it "keeps duplicate_index over unused_index for the same index" do
    idx = findings.find { |f| f.index == "idx_users_on_name" }
    expect(idx.type).to eq(:duplicate_index)               # 0.8 beats unused_index 0.55
  end

  it "does not double-count reclaimable bytes for a collapsed column" do
    token = findings.find { |f| f.column == "legacy_token" && f.index.nil? }
    expect(token.reclaimable_bytes).to eq(16 * 5000)
  end
end
