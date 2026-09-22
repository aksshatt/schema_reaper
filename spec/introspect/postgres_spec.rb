# frozen_string_literal: true

# Exercises the live-database introspection layer. CI has no PostgreSQL service,
# so these specs are opt-in — point them at a throwaway database:
#
#   SCHEMA_REAPER_TEST_DATABASE_URL=postgres://localhost/schema_reaper_test bundle exec rspec
RSpec.describe SchemaReaper::Introspect::Postgres do
  # No live database needed -- stubs the connection to exercise error
  # wrapping without a real Postgres instance.
  describe "query error handling" do
    before { require "pg" }

    def introspector_with(conn)
      allow(PG).to receive(:connect).and_return(conn)
      described_class.new("postgres://fake")
    end

    it "wraps a query-time PG::Error as SchemaReaper::Error instead of leaking it raw" do
      conn = instance_double(PG::Connection)
      allow(conn).to receive(:exec).and_raise(PG::Error, "relation does not exist")
      introspector = introspector_with(conn)

      expect { introspector.send(:exec, "SELECT 1") }
        .to raise_error(SchemaReaper::Error, /query against the database failed/)
    end

    it "still falls back to nil when primary_key_for's query fails, now that exec wraps the error" do
      conn = instance_double(PG::Connection)
      allow(conn).to receive(:exec_params).and_raise(PG::Error, "no such relation")
      introspector = introspector_with(conn)

      expect(introspector.send(:primary_key_for, "ghost_table")).to be_nil
    end
  end

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

        DROP TABLE IF EXISTS schema_reaper_expr_idx;
        -- Two expression key columns ahead of a plain one. pg_index.indkey
        -- stores 0 for an expression position; joining that against
        -- pg_attribute by attnum matches nothing, so the naive approach
        -- silently drops both expressions and reports this index as just
        -- (user_id). A bare index on :user_id then looks like a covered
        -- duplicate of a key it is not actually a prefix of.
        CREATE TABLE schema_reaper_expr_idx (
          id bigserial PRIMARY KEY,
          data jsonb,
          read_at timestamp,
          created_at timestamp,
          user_id bigint
        );
        CREATE INDEX idx_expr_then_user
          ON schema_reaper_expr_idx (
            (COALESCE(read_at, created_at)), (data ->> 'kind'), user_id
          );
        CREATE INDEX idx_user_only
          ON schema_reaper_expr_idx (user_id);
      SQL
    end

    after(:all) do
      @conn&.exec("DROP TABLE IF EXISTS schema_reaper_idx_order")
      @conn&.exec("DROP TABLE IF EXISTS schema_reaper_composite_pk")
      @conn&.exec("DROP TABLE IF EXISTS schema_reaper_expr_idx")
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

    def expr_index_named(name)
      table = described_class.new(db_url).call.tables.find { |t| t.name == "schema_reaper_expr_idx" }
      table.indexes.find { |i| i.name == name }
    end

    it "renders expression key columns instead of dropping them" do
      columns = expr_index_named("idx_expr_then_user").columns
      expect(columns.length).to eq(3)
      expect(columns[0]).to include("COALESCE")
      expect(columns[1]).to include("data ->>")
      expect(columns[2]).to eq("user_id")
    end

    it "splits a comma inside an expression as part of that expression, not as a column boundary" do
      expect(expr_index_named("idx_expr_then_user").columns[0]).to include("read_at, created_at")
    end

    it "does not treat a plain index as covered by one whose leading columns are expressions" do
      expr_led = expr_index_named("idx_expr_then_user")
      user_only = expr_index_named("idx_user_only")

      expect(expr_led.covers?(user_only)).to be(false)
    end
  end
end
