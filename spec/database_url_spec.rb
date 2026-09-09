# frozen_string_literal: true

require "tmpdir"

RSpec.describe SchemaReaper::DatabaseUrl do
  def with_db_yml(body)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "database.yml"), body)
      yield dir
    end
  end

  it "builds a socket URL from a plain development section" do
    with_db_yml(<<~YML) do |dir|
      development:
        adapter: postgresql
        database: myapp_development
    YML
      expect(described_class.from_rails(root: dir)).to eq("postgresql:///myapp_development")
    end
  end

  it "resolves YAML aliases and host/port/credentials" do
    with_db_yml(<<~YML) do |dir|
      default: &default
        adapter: postgresql
        host: db.internal
        port: 5433
        username: app
        password: secret
      development:
        <<: *default
        database: shop
    YML
      expect(described_class.from_rails(root: dir))
        .to eq("postgresql://app:secret@db.internal:5433/shop")
    end
  end

  it "renders ERB and reads ENV" do
    with_db_yml(<<~YML) do |dir|
      development:
        adapter: postgresql
        database: <%= ENV.fetch("SR_TEST_DB", "fallback_db") %>
    YML
      expect(described_class.from_rails(root: dir)).to eq("postgresql:///fallback_db")
    end
  end

  it "prefers an explicit url: key" do
    with_db_yml(<<~YML) do |dir|
      development:
        url: postgres://u@h/exact
        adapter: postgresql
        database: ignored
    YML
      expect(described_class.from_rails(root: dir)).to eq("postgres://u@h/exact")
    end
  end

  it "picks the primary of a Rails 6 multi-database section" do
    with_db_yml(<<~YML) do |dir|
      development:
        primary:
          adapter: postgresql
          database: main_db
        replica:
          adapter: postgresql
          database: replica_db
          replica: true
    YML
      expect(described_class.from_rails(root: dir)).to eq("postgresql:///main_db")
    end
  end

  it "honours SCHEMA_REAPER_ENV / RAILS_ENV" do
    with_db_yml(<<~YML) do |dir|
      development:
        adapter: postgresql
        database: dev_db
      staging:
        adapter: postgresql
        database: staging_db
    YML
      expect(described_class.from_rails(root: dir, env: "staging"))
        .to eq("postgresql:///staging_db")
    end
  end

  it "returns nil for a non-Postgres adapter" do
    with_db_yml(<<~YML) do |dir|
      development:
        adapter: mysql2
        database: myapp
    YML
      expect(described_class.from_rails(root: dir)).to be_nil
    end
  end

  it "returns nil when there is no database.yml" do
    Dir.mktmpdir { |dir| expect(described_class.from_rails(root: dir)).to be_nil }
  end
end

RSpec.describe SchemaReaper::Config do
  it "resolves database_url from .schema_reaper.yml first, then ENV, then database.yml" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "database.yml"), <<~YML)
        development:
          adapter: postgresql
          database: from_yml
      YML

      cfg_path = File.join(dir, ".schema_reaper.yml")

      # 3. database.yml fallback
      File.write(cfg_path, "scan_paths: [app]\n")
      expect(described_class.load(cfg_path).database_url).to eq("postgresql:///from_yml")

      # 2. ENV wins over database.yml
      begin
        ENV["DATABASE_URL"] = "postgres:///from_env"
        expect(described_class.load(cfg_path).database_url).to eq("postgres:///from_env")
      ensure
        ENV.delete("DATABASE_URL")
      end

      # 1. explicit config wins over everything
      File.write(cfg_path, "database_url: postgres:///explicit\n")
      expect(described_class.load(cfg_path).database_url).to eq("postgres:///explicit")
    end
  end
end
