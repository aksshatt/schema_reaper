# frozen_string_literal: true

# Exercises the live-database introspection layer. CI has no PostgreSQL service,
# so these specs are opt-in — point them at a throwaway database:
#
#   SCHEMA_REAPER_TEST_DATABASE_URL=postgres://localhost/schema_reaper_test bundle exec rspec
RSpec.describe SchemaReaper::Introspect::Postgres do
  url = ENV.fetch("SCHEMA_REAPER_TEST_DATABASE_URL", nil)

  if url.nil? || url.empty?
    it "is skipped without a test database" do
      skip "set SCHEMA_REAPER_TEST_DATABASE_URL to a throwaway database to run introspection specs"
    end
  else
    before(:all) do
      require "pg"
      @conn = PG.connect(url)
      # Column order is (id, account_id, created_at) but the index is keyed
      # (created_at, account_id) — the reverse. Ordering columns by pg_attribute
      # .attnum would report (account_id, created_at) and make this index look
      # like it covers a leading-edge index on account_id.
      @conn.exec(<<~SQL)
        DROP TABLE IF EXISTS schema_reaper_idx_order;
        CREATE TABLE schema_reaper_idx_order (
          id bigserial PRIMARY KEY,
          account_id bigint,
          created_at timestamp
        );
        CREATE INDEX idx_created_account
          ON schema_reaper_idx_order (created_at, account_id);

        DROP TABLE IF EXISTS schema_reaper_composite_pk;
        -- Key order (group_id, user_id) is the reverse of column order, so a
        -- query that does not sort by the index key reports them backwards.
        CREATE TABLE schema_reaper_composite_pk (
          user_id bigint NOT NULL,
          group_id bigint NOT NULL,
          PRIMARY KEY (group_id, user_id)
        );
      SQL
    end

    after(:all) do
      @conn&.exec("DROP TABLE IF EXISTS schema_reaper_idx_order")
      @conn&.exec("DROP TABLE IF EXISTS schema_reaper_composite_pk")
      @conn&.close
    end

    let(:db_url) { url }

    def index_named(name)
      table = described_class.new(db_url).call.tables.find { |t| t.name == "schema_reaper_idx_order" }
      table.indexes.find { |i| i.name == name }
    end

    it "returns index columns in index-key order, not table order" do
      expect(index_named("idx_created_account").columns).to eq(%w[created_at account_id])
    end

    it "does not treat a non-leading column as covered by the composite index" do
      composite = index_named("idx_created_account")
      account_only = SchemaReaper::Index.new(
        name: "idx_account", columns: %w[account_id],
        unique: false, primary: false, scans: nil
      )

      expect(composite.covers?(account_only)).to be(false)
    end

    it "returns every primary-key column in key order" do
      table = described_class.new(db_url).call.tables
                             .find { |t| t.name == "schema_reaper_composite_pk" }

      expect(table.primary_key_columns).to eq(%w[group_id user_id])
      expect(table.primary_key?("user_id")).to be(true)
    end
  end
end
