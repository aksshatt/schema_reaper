# frozen_string_literal: true

require "tmpdir"
require "active_record"

RSpec.describe SchemaReaper::MigrationGenerator do
  it "writes two syntactically valid, distinct migration files" do
    Dir.mktmpdir do |dir|
      paths = described_class.new(table: "users", column: "legacy_api_token", dir: dir).call

      expect(paths.size).to eq(2)
      expect(paths.uniq).to eq(paths) # distinct timestamps

      ignore, drop = paths.sort
      ignore_src = File.read(ignore)
      drop_src = File.read(drop)

      expect(RubyVM::InstructionSequence.compile(ignore_src)).to be_a(RubyVM::InstructionSequence)
      expect(RubyVM::InstructionSequence.compile(drop_src)).to be_a(RubyVM::InstructionSequence)

      expect(ignore_src).to include("class IgnoreUsersLegacyApiTokenColumn")
      expect(ignore_src).to include("%w[legacy_api_token]")
      expect(ignore_src).not_to include(" \\\n") # no fragile line-continuation in output

      expect(drop_src).to include("remove_column :users, :legacy_api_token")
      expect(drop_src).to include("ActiveRecord::IrreversibleMigration")
    end
  end

  it "targets the loaded ActiveRecord minor version" do
    Dir.mktmpdir do |dir|
      path = described_class.new(table: "posts", column: "old", dir: dir).call.first
      expected = ActiveRecord::VERSION::STRING.split(".").first(2).join(".")
      expect(File.read(path)).to include("ActiveRecord::Migration[#{expected}]")
    end
  end

  it "singularizes an irregular plural table name in the model reference" do
    Dir.mktmpdir do |dir|
      path = described_class.new(table: "addresses", column: "old", dir: dir).call.first
      expect(File.read(path)).to include("Address model")
      expect(File.read(path)).not_to include("Addresse model")
    end
  end

  describe "index removal" do
    it "writes one concurrent, transaction-free remove_index migration" do
      Dir.mktmpdir do |dir|
        paths = described_class.new(table: "users", index: "index_users_on_email", dir: dir).call
        src = File.read(paths.first)

        expect(paths.size).to eq(1)
        expect(RubyVM::InstructionSequence.compile(src)).to be_a(RubyVM::InstructionSequence)
        expect(src).to include("disable_ddl_transaction!")
        expect(src).to include("remove_index :users, name: :index_users_on_email, algorithm: :concurrently")
      end
    end
  end

  describe "table removal" do
    it "writes one irreversible drop_table migration, quoting a schema-qualified name" do
      Dir.mktmpdir do |dir|
        path = described_class.new(table: "billing.invoices", dir: dir).call.first
        src = File.read(path)

        expect(File.basename(path)).to end_with("_drop_billing_invoices.rb")
        expect(RubyVM::InstructionSequence.compile(src)).to be_a(RubyVM::InstructionSequence)
        expect(src).to include('drop_table :"billing.invoices"')
        expect(src).to include("class DropBillingInvoicesTable")
        expect(src).to include("ActiveRecord::IrreversibleMigration")
      end
    end
  end

  it "refuses both a column and an index" do
    expect { described_class.new(table: "users", column: "a", index: "b") }.to raise_error(ArgumentError)
  end
end
