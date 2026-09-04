# frozen_string_literal: true

RSpec.describe "Runner finding de-duplication" do
  let(:config) do
    SchemaReaper::Config.new(
      SchemaReaper::Config::DEFAULTS.merge(
        "scan_paths" => [], "view_globs" => [], "gem_awareness" => false
      )
    )
  end

  let(:schema) do
    fake_schema(
      fake_table("legacy_events", row_count: 0, primary_key: "id", columns: [
                   { name: "id" }, { name: "payload", null: true }, { name: "kind", null: true }
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

  it "collapses column findings into the table finding when the table is dead" do
    findings = SchemaReaper::Runner.new(
      config: config, introspector: introspector, runtime: SchemaReaper::Runtime::Report.empty
    ).run

    expect(findings.map(&:type).uniq).to eq([:dead_table])
    expect(findings.size).to eq(1)
  end
end
