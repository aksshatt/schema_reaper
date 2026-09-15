# frozen_string_literal: true

require "yaml"
require_relative "database_url"

module SchemaReaper
  # Loaded from .schema_reaper.yml at the project root. Every key has a default
  # so a missing file still yields a usable config.
  class Config
    DEFAULTS = {
      "database_url" => nil,          # falls back to ENV["DATABASE_URL"]
      "scan_paths" => %w[app lib config],
      "view_globs" => %w[
        app/**/*.erb app/**/*.haml app/**/*.slim app/**/*.jbuilder
      ],
      "ignore" => {
        "tables" => %w[schema_migrations ar_internal_metadata],
        "columns" => []               # strings, or "/regex/" for a pattern
      },
      "always_keep_columns" => %w[id created_at updated_at type],
      "gem_awareness" => true,        # auto-whitelist columns owned by known gems
      "min_age_days" => 14,
      "runtime_log" => ".schema_reaper/runtime.jsonl",
      "history_log" => ".schema_reaper/history.jsonl",
      "baseline" => ".schema_reaper/baseline.json",
      "database_yml" => "config/database.yml", # Rails fallback for the connection
      "require" => [] # extra files to load (custom analyzers)
    }.freeze

    def self.load(path = ".schema_reaper.yml")
      raw = File.exist?(path) ? (safe_load_file(path) || {}) : {}
      new(deep_merge(DEFAULTS, raw), root: File.dirname(File.expand_path(path)))
    end

    # Psych.safe_load_file arrived in Psych 3.3 (Ruby 3.0), but the gem supports
    # Ruby 2.7. Reading the file ourselves is equivalent -- safe_load_file
    # defaults to aliases: false, which is what safe_load does too.
    def self.safe_load_file(path)
      return YAML.safe_load_file(path) if YAML.respond_to?(:safe_load_file)

      YAML.safe_load(File.read(path))
    end

    def self.deep_merge(base, override)
      base.merge(override) do |_key, a, b|
        a.is_a?(Hash) && b.is_a?(Hash) ? deep_merge(a, b) : b
      end
    end

    def initialize(data, root: Dir.pwd)
      @data = data
      @root = root
    end

    # Resolution order:
    #   1. database_url: in .schema_reaper.yml
    #   2. ENV["DATABASE_URL"]
    #   3. config/database.yml for the current environment (Rails apps)
    def database_url
      @data["database_url"] ||
        ENV.fetch("DATABASE_URL", nil) ||
        DatabaseUrl.from_rails(root: @root, path: @data["database_yml"])
    end

    def scan_paths
      @data["scan_paths"]
    end

    def view_globs
      @data["view_globs"]
    end

    def ignore_tables
      @data.dig("ignore", "tables").to_a
    end

    def min_age_days
      @data["min_age_days"]
    end

    def baseline_path
      @data["baseline"]
    end

    def runtime_log
      @data["runtime_log"]
    end

    def history_log
      @data["history_log"]
    end

    def gem_awareness?
      @data["gem_awareness"] != false
    end

    def require_paths
      @data["require"].to_a
    end

    def always_keep_columns
      @data["always_keep_columns"].to_a
    end

    # Returns true when a column name should be ignored outright.
    def ignored_column?(name)
      matchers.any? { |m| m.is_a?(Regexp) ? m.match?(name) : m == name }
    end

    private

    def matchers
      @matchers ||= @data.dig("ignore", "columns").to_a.map do |entry|
        if entry.is_a?(String) && entry.start_with?("/") && entry.end_with?("/")
          Regexp.new(entry[1..-2])
        else
          entry
        end
      end
    end
  end
end
