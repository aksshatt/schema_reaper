# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe SchemaReaper::SchemaLocator do
  def finding(**attrs)
    SchemaReaper::Finding.new({ type: :dead_column, severity: :low, confidence: 0.5, bytes_per_row: 0,
                                evidence: [], suggested_fix: "" }.merge(attrs))
  end

  def with_schema(path, body)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "db"))
      File.write(File.join(dir, path), body)
      yield described_class.new(root: dir)
    end
  end

  let(:schema_rb) do
    <<~RUBY
      ActiveRecord::Schema[7.1].define(version: 1) do
        create_table "accounts", force: :cascade do |t|
          t.string "email"
        end

        create_table "users", force: :cascade do |t|
          t.string "email"
          t.string "legacy_token"
          t.index ["email"], name: "index_users_on_email"
        end
      end
    RUBY
  end

  it "points a column finding at its line inside the right table" do
    with_schema("db/schema.rb", schema_rb) do |loc|
      expect(loc.locate(finding(table: "users", column: "email")).line).to eq(7)
      expect(loc.locate(finding(table: "accounts", column: "email")).line).to eq(3)
    end
  end

  it "points an index finding at its t.index line, and a table finding at create_table" do
    with_schema("db/schema.rb", schema_rb) do |loc|
      expect(loc.locate(finding(table: "users", column: "email", index: "index_users_on_email")).line).to eq(9)
      expect(loc.locate(finding(table: "users")).line).to eq(6)
    end
  end

  it "reads structure.sql too" do
    sql = <<~SQL
      CREATE TABLE public.users (
          id bigint NOT NULL,
          legacy_token character varying
      );

      CREATE INDEX idx_users_token ON public.users USING btree (legacy_token);
    SQL
    with_schema("db/structure.sql", sql) do |loc|
      expect(loc.locate(finding(table: "users", column: "legacy_token")).path).to eq("db/structure.sql")
      expect(loc.locate(finding(table: "users", column: "legacy_token")).line).to eq(3)
      expect(loc.locate(finding(table: "users", index: "idx_users_token")).line).to eq(6)
    end
  end

  it "returns nil without a schema file" do
    Dir.mktmpdir { |dir| expect(described_class.new(root: dir).locate(finding(table: "users"))).to be_nil }
  end
end
