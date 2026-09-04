# frozen_string_literal: true

RSpec.describe SchemaReaper::Static::Scanner do
  let(:root) { File.expand_path("../fixtures", __dir__) }
  let(:config) do
    SchemaReaper::Config.new(
      SchemaReaper::Config::DEFAULTS.merge("scan_paths" => %w[app], "view_globs" => [])
    )
  end

  subject(:tokens) { described_class.new(config, root: root).call }

  it "picks up symbol references" do
    expect(tokens).to include("email", "state")
  end

  it "picks up method-name references" do
    expect(tokens).to include("first_name", "last_name", "display_name")
  end

  it "picks up words inside SQL string literals" do
    expect(tokens).to include("email")
  end

  it "does not invent tokens" do
    expect(tokens).not_to include("legacy_ssn_hash")
  end
end
