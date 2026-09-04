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
end
