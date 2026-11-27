# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe "scan result: model scope, keep comments, cache" do
  let(:root) { File.expand_path("../fixtures/scoped", __dir__) }

  def config(extra = {})
    SchemaReaper::Config.new(
      SchemaReaper::Config::DEFAULTS.merge("scan_paths" => %w[app], "view_globs" => []).merge(extra)
    )
  end

  let(:result) { SchemaReaper::Static::Scanner.new(config, root: root).scan }

  it "maps each model file to its tables" do
    expect(result.models.to_h { |m| [File.basename(m.path), m.tables] }).to eq(
      "order.rb" => %w[orders],
      "user.rb" => %w[users],
      "line_item.rb" => %w[order_lines],             # self.table_name
      "admin_user.rb" => %w[users],                  # STI subclass: the parent's table
      "widget.rb" => %w[widgets],                    # via a second abstract base
      "invoice.rb" => %w[invoices billing_invoices]  # module Billing: either default
    )
  end

  it "does not place abstract bases, POROs or concerns -- their names stay shared" do
    placed = result.models.map { |m| File.basename(m.path) }
    expect(placed).not_to include("application_record.rb", "legacy_record.rb", "report_form.rb", "taggable.rb")
    expect(result.shared).to include("abstract_helper", "form_field", "concern_hook")
  end

  it "keeps non-model tokens shared and model tokens out of it" do
    expect(result.shared).to include("welcome")
    expect(result.shared).not_to include("status")
  end

  it "collects keep comments with their reason" do
    expect(result.keeps).to eq("legacy_token" => "read by the billing ETL",
                               "users.api_key" => "read by the billing ETL")
  end

  describe "column_scope" do
    def dead_columns(scope)
      schema = fake_schema(fake_table("users", columns: [{ name: "id" }, { name: "status" }, { name: "nickname" },
                                                         { name: "email" }]))
      ctx = context_for(schema: schema, used: result.tokens.to_a, config: config("column_scope" => scope))
      ctx.scan = result
      SchemaReaper::Analyzers::DeadColumn.new(ctx).call.map(&:column)
    end

    it "global: another model's use of the name hides the column" do
      expect(dead_columns("global")).to be_empty
    end

    it "model: only this model's file, or one that mentions it, counts" do
      # Order mentions `user`, so its `nickname` counts for users; its
      # `status` is about orders too, but Order also mentions user -- the
      # heuristic stays permissive there. `status` on a table Order never
      # mentions is what gets caught:
      expect(dead_columns("model")).to be_empty

      schema = fake_schema(fake_table("accounts", columns: [{ name: "id" }, { name: "status" }]))
      ctx = context_for(schema: schema, used: result.tokens.to_a, config: config("column_scope" => "model"))
      ctx.scan = result
      expect(SchemaReaper::Analyzers::DeadColumn.new(ctx).call.map(&:column)).to eq(["status"])
    end
  end

  it "silences findings named by a keep comment", :scan_cache do
    schema = fake_schema(fake_table("users", columns: [
                                      { name: "id" }, { name: "legacy_token" }, { name: "api_key" }, { name: "junk" }
                                    ]))
    findings = SchemaReaper::Runner.new(config: config("scan_cache" => nil), root: root,
                                        introspector: -> { schema },
                                        runtime: SchemaReaper::Runtime::Report.empty,
                                        only: %w[dead_column]).run
    expect(findings.map(&:column)).to eq(["junk"])
  end

  describe "cache", :scan_cache do
    it "reuses unchanged files and rescans changed ones" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "app"))
        file = File.join(dir, "app", "thing.rb")
        File.write(file, "def alpha; end\n")
        cfg = config("scan_cache" => ".cache/scan.json")

        expect(SchemaReaper::Static::Scanner.new(cfg, root: dir).call).to include("alpha")
        expect(File.exist?(File.join(dir, ".cache/scan.json"))).to be(true)

        allow(Prism).to receive(:parse).and_call_original
        SchemaReaper::Static::Scanner.new(cfg, root: dir).call
        expect(Prism).not_to have_received(:parse)

        File.write(file, "def beta_gamma; end\n")
        File.utime(Time.now + 5, Time.now + 5, file)
        expect(SchemaReaper::Static::Scanner.new(cfg, root: dir).call).to include("beta_gamma")
      end
    end
  end
end
