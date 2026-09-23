# frozen_string_literal: true

RSpec.describe SchemaReaper::Config do
  def config_with(overrides)
    described_class.new(described_class::DEFAULTS.merge(overrides))
  end

  it "exposes the simple accessors straight from the merged data" do
    config = config_with(
      "min_age_days" => 30,
      "baseline" => ".schema_reaper/custom_baseline.json",
      "runtime_log" => "log/custom_runtime.jsonl",
      "history_log" => "log/custom_history.jsonl",
      "always_keep_columns" => %w[id type]
    )

    expect(config.min_age_days).to eq(30)
    expect(config.baseline_path).to eq(".schema_reaper/custom_baseline.json")
    expect(config.runtime_log).to eq("log/custom_runtime.jsonl")
    expect(config.history_log).to eq("log/custom_history.jsonl")
    expect(config.always_keep_columns).to eq(%w[id type])
  end

  describe "#ignored_column?" do
    it "matches a plain string exactly" do
      config = config_with("ignore" => { "columns" => ["legacy_flag"] })
      expect(config.ignored_column?("legacy_flag")).to be true
      expect(config.ignored_column?("legacy_flags")).to be false
    end

    it "matches a /regex/-style string as a pattern" do
      config = config_with("ignore" => { "columns" => ["/_cache\\z/"] })
      expect(config.ignored_column?("thumbnail_cache")).to be true
      expect(config.ignored_column?("cache_thumbnail")).to be false
    end

    it "is false when no columns are configured to ignore" do
      config = config_with({})
      expect(config.ignored_column?("anything")).to be false
    end
  end

  describe "#gem_awareness?" do
    it "defaults to true" do
      expect(config_with({}).gem_awareness?).to be true
    end

    it "is false only when explicitly disabled" do
      expect(config_with("gem_awareness" => false).gem_awareness?).to be false
    end
  end

  it "#require_paths returns an empty array, not nil, when unset" do
    expect(config_with({}).require_paths).to eq([])
  end
end
