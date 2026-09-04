# frozen_string_literal: true

RSpec.describe SchemaReaper::Runner do
  let(:root) { File.expand_path("fixtures", __dir__) }
  let(:config) do
    SchemaReaper::Config.new(
      SchemaReaper::Config::DEFAULTS.merge(
        "scan_paths" => %w[app], "view_globs" => [], "gem_awareness" => false
      )
    )
  end

  let(:introspector) do
    double(call: fake_schema(
      fake_table("users", row_count: 20, columns: [
                   { name: "id" },
                   { name: "email" },
                   { name: "abandoned_flag", null: true }
                 ])
    ))
  end

  it "runs scan + analyzers end to end without a database" do
    findings = described_class.new(
      config: config, root: root, introspector: introspector,
      runtime: SchemaReaper::Runtime::Report.empty
    ).run

    dead = findings.select { |f| f.type == :dead_column }
    expect(dead.map(&:column)).to include("abandoned_flag")
    expect(dead.map(&:column)).not_to include("email")
  end
end
