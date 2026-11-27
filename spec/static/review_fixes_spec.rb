# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

RSpec.describe "PR #26 review fixes: scanner" do
  def write_app(dir, files)
    files.each do |rel, body|
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, body)
    end
  end

  def config(extra = {})
    SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.merge("scan_paths" => %w[app], "view_globs" => [],
                                                                  "scan_cache" => nil).merge(extra))
  end

  describe "models keyed by full class path" do
    let(:files) do
      {
        "app/models/user.rb" => "class User < ApplicationRecord\nend\n",
        "app/models/admin/user.rb" => "module Admin\n  class User < ApplicationRecord\n    " \
                                      "def x; clearance_level; end\n  end\nend\n",
        "app/models/admin/manager.rb" => "module Admin\n  class Manager < User\n  end\nend\n",
        "app/models/guest.rb" => "class Guest < ::User\nend\n"
      }
    end

    it "keeps User and Admin::User apart, so neither overwrites the other's tables" do
      Dir.mktmpdir do |dir|
        write_app(dir, files)
        models = SchemaReaper::Static::Scanner.new(config, root: dir).scan.models
        by_file = models.to_h { |m| [m.path.delete_prefix("#{dir}/app/models/"), m.tables] }

        expect(by_file["user.rb"]).to eq(%w[users])
        expect(by_file["admin/user.rb"]).to eq(%w[users admin_users])
        expect(by_file["admin/manager.rb"]).to eq(%w[users admin_users]) # STI: Admin::User, not ::User
        expect(by_file["guest.rb"]).to eq(%w[users])                     # ::User is the top-level one
      end
    end

    it "does not report a column used only in the namespaced model as dead (mitkush's repro)" do
      Dir.mktmpdir do |dir|
        write_app(dir, files)
        scan = SchemaReaper::Static::Scanner.new(config, root: dir).scan
        schema = fake_schema(fake_table("admin_users", columns: [{ name: "id" }, { name: "clearance_level" }]))
        ctx = context_for(schema: schema, used: scan.tokens.to_a, config: config("column_scope" => "model"))
        ctx.scan = scan

        expect(SchemaReaper::Analyzers::DeadColumn.new(ctx).call).to be_empty
      end
    end
  end

  describe "scan cache across processes", :scan_cache do
    it "hits in a fresh process (no per-process #hash seed in the key)" do
      Dir.mktmpdir do |dir|
        write_app(dir, "app/thing.rb" => "def alpha; end\n")
        lib = File.expand_path("../../lib", __dir__)
        script = <<~RUBY
          require "logger"
          require "schema_reaper"
          cfg = SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.merge(
            "scan_paths" => %w[app], "view_globs" => [], "scan_cache" => ".cache.json"))
          parses = 0
          Prism.singleton_class.prepend(Module.new { define_method(:parse) { |*a, **k| parses += 1; super(*a, **k) } })
          SchemaReaper::Static::Scanner.new(cfg, root: #{dir.inspect}).call
          print parses
        RUBY
        runs = Array.new(2) do
          out, status = Open3.capture2e(RbConfig.ruby, "-I", lib, "-e", script)
          expect(status).to be_success, out
          out.to_i
        end

        expect(runs).to eq([1, 0])
      end
    end
  end
end
