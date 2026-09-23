# frozen_string_literal: true

# SchemaReaper.reporter -- the --format dispatch the CLI and rake tasks use.
RSpec.describe SchemaReaper do
  describe ".reporter" do
    {
      "table" => SchemaReaper::Reporters::Table,
      "json" => SchemaReaper::Reporters::Json,
      "markdown" => SchemaReaper::Reporters::Markdown,
      "sarif" => SchemaReaper::Reporters::Sarif
    }.each do |name, klass|
      it "resolves #{name.inspect} to #{klass}" do
        expect(described_class.reporter(name)).to eq(klass)
      end
    end

    it "falls back to Table for an unrecognized format name" do
      expect(described_class.reporter("yaml")).to eq(SchemaReaper::Reporters::Table)
    end
  end
end
