# frozen_string_literal: true

# Exercises the live-database introspection layer. CI runs these against a
# PostgreSQL service; locally they are opt-in — point them at a throwaway database:
#
#   SCHEMA_REAPER_TEST_DATABASE_URL=postgres://localhost/schema_reaper_test bundle exec rspec
RSpec.describe SchemaReaper::Introspect::Postgres do
  # No live database needed -- stubs the connection to exercise error
  # wrapping without a real Postgres instance.
  it "explains a missing pg gem instead of failing with a NameError" do
    allow(SchemaReaper::Introspect).to receive(:require).with("pg")
                                                        .and_raise(LoadError, "cannot load such file -- pg")

    expect { described_class.new("postgres://fake") }
      .to raise_error(SchemaReaper::Error, /needs the `pg` gem/)
  end

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

      expect(introspector.send(:primary_key_for, "public", "ghost_table")).to be_nil
    end

    it "wraps a real connection failure as SchemaReaper::Error, not a raw PG::ConnectionBad" do
      # A genuinely refused connection (port 1: nothing listens there, so it
      # fails instantly -- no live test database needed, and no risk of a
      # slow/hanging spec from an unreachable host).
      expect { described_class.new("postgres://localhost:1/nonexistent?connect_timeout=1") }
        .to raise_error(SchemaReaper::Error, /could not connect to the database/)
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

        -- Analysed with real data, unlike the tables above -- reltuples and
        -- pg_stats are both populated only after ANALYZE, so this is what
        -- exercises row_count_for's positive branch and column_stats_for's
        -- populated branch (both otherwise unreachable: a freshly-created,
        -- never-analysed table reports reltuples = -1 and has zero pg_stats
        -- rows).
        DROP TABLE IF EXISTS schema_reaper_analysed;
        CREATE TABLE schema_reaper_analysed (
          id bigserial PRIMARY KEY,
          always_present text NOT NULL,
          sometimes_null text
        );
        INSERT INTO schema_reaper_analysed (always_present, sometimes_null)
        SELECT 'x', CASE WHEN i % 2 = 0 THEN NULL ELSE 'y' END
        FROM generate_series(1, 100) AS i;
        ANALYZE schema_reaper_analysed;
      SQL
    end

    after(:all) do
      @conn&.exec("DROP TABLE IF EXISTS schema_reaper_idx_order")
      @conn&.exec("DROP TABLE IF EXISTS schema_reaper_composite_pk")
      @conn&.exec("DROP TABLE IF EXISTS schema_reaper_expr_idx")
      @conn&.exec("DROP TABLE IF EXISTS schema_reaper_analysed")
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

    def analysed_table
      described_class.new(db_url).call.tables.find { |t| t.name == "schema_reaper_analysed" }
    end

    it "reports a real row-count estimate once the table has been analysed" do
      # reltuples is -1 (unknown) for a table that's never been ANALYZEd --
      # this table was, in the before(:all) setup, so the positive branch
      # of row_count_for is what's under test here.
      expect(analysed_table.row_count).to be_within(20).of(100) # planner estimate, not exact
    end

    it "reports null_fraction and distinct_values from pg_stats once analysed" do
      always_present = analysed_table.column("always_present")
      sometimes_null = analysed_table.column("sometimes_null")

      expect(always_present.null_fraction).to eq(0.0)
      expect(sometimes_null.null_fraction).to be_within(0.15).of(0.5)
      expect(sometimes_null.distinct_values).not_to be_nil
    end

    it "uses pg_stats.avg_width for column bytes once analysed" do
      expect(analysed_table.column("always_present").bytes).to eq(2) # 'x' = 1-byte header + 1 byte
    end

    # Same table name in two schemas, each with a same-named FK constraint and
    # a different row count -- the shape that made unqualified lookups mix
    # them up.
    describe "schema qualification" do
      before(:all) do
        @conn.exec(<<~SQL)
          DROP SCHEMA IF EXISTS sr_other CASCADE;
          DROP TABLE IF EXISTS sr_twin, sr_parent CASCADE;
          CREATE SCHEMA sr_other;
          CREATE TABLE sr_parent (id bigserial PRIMARY KEY);
          CREATE TABLE sr_twin (id bigserial PRIMARY KEY, parent_id bigint,
            CONSTRAINT sr_fk FOREIGN KEY (parent_id) REFERENCES sr_parent (id));
          CREATE TABLE sr_other.sr_twin (code text PRIMARY KEY, other_parent_id bigint,
            CONSTRAINT sr_fk FOREIGN KEY (other_parent_id) REFERENCES sr_parent (id),
            CONSTRAINT sr_fk_dup FOREIGN KEY (other_parent_id) REFERENCES sr_parent (id));
          INSERT INTO sr_other.sr_twin SELECT g::text, NULL FROM generate_series(1, 500) g;
          ANALYZE sr_twin; ANALYZE sr_other.sr_twin;
          -- An integer key whose sequence is 90% through the integer range.
          DROP TABLE IF EXISTS sr_legacy;
          CREATE TABLE sr_legacy (id serial PRIMARY KEY);
          SELECT setval('sr_legacy_id_seq', 1932735283);
        SQL
      end

      after(:all) do
        @conn&.exec("DROP SCHEMA IF EXISTS sr_other CASCADE")
        @conn&.exec("DROP TABLE IF EXISTS sr_twin, sr_parent, sr_legacy CASCADE")
      end

      let(:db) { described_class.new(db_url, schemas: %w[public sr_other]).call }

      it "keeps each schema's row count, primary key and foreign keys to itself" do
        pub = db.table("sr_twin")
        other = db.table("sr_other.sr_twin")

        expect(pub.row_count).to eq(0)
        expect(other.row_count).to be_within(50).of(500)
        expect(pub.primary_key_columns).to eq(%w[id])
        expect(other.primary_key_columns).to eq(%w[code])
        expect(pub.foreign_keys).to eq(%w[parent_id])
        expect(other.foreign_keys).to eq(%w[other_parent_id])
        expect(other.foreign_key_constraints.map(&:name)).to eq(%w[sr_fk sr_fk_dup])
        expect(other.foreign_key_constraints.map(&:references).uniq).to eq(%w[sr_parent])
      end

      it "only scans public by default" do
        expect(described_class.new(db_url).call.table("sr_other.sr_twin")).to be_nil
      end

      it "reports a column-owned sequence against the column type's ceiling" do
        seq = db.sequences.find { |s| s.table == "sr_legacy" }

        expect(seq.column).to eq("id")
        expect(seq.column_type).to eq("integer")
        expect(seq.max_value).to eq(2_147_483_647)
        expect(seq.used_fraction).to be_within(0.01).of(0.9)
      end
    end

    describe "accuracy on partitions, FK behaviour and sequences" do
      before(:all) do
        @conn.exec(<<~SQL)
          DROP TABLE IF EXISTS sr_events, sr_fk_parent, sr_fk_child, sr_cyc CASCADE;
          CREATE TABLE sr_events (id bigint, kind text, at date NOT NULL) PARTITION BY RANGE (at);
          CREATE TABLE sr_events_2026_01 PARTITION OF sr_events FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
          CREATE TABLE sr_events_2026_02 PARTITION OF sr_events FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
          CREATE INDEX idx_sr_events_kind ON sr_events (kind);
          INSERT INTO sr_events SELECT g, 'k' || (g % 3), DATE '2026-01-01' + (g % 50) FROM generate_series(1, 1000) g;
          ANALYZE sr_events;

          CREATE TABLE sr_fk_parent (id bigint PRIMARY KEY);
          CREATE TABLE sr_fk_child (id bigint PRIMARY KEY, parent_id bigint,
            CONSTRAINT fk_a FOREIGN KEY (parent_id) REFERENCES sr_fk_parent (id),
            CONSTRAINT fk_b FOREIGN KEY (parent_id) REFERENCES sr_fk_parent (id) ON DELETE CASCADE,
            CONSTRAINT fk_c FOREIGN KEY (parent_id) REFERENCES sr_fk_parent (id));

          CREATE TABLE sr_cyc (id serial PRIMARY KEY);
          ALTER SEQUENCE sr_cyc_id_seq CYCLE;
          SELECT setval('sr_cyc_id_seq', 2000000000);
        SQL
        # Use the index from a separate connection and close it: before
        # PostgreSQL 15 a backend's pending stats are only flushed when it
        # goes idle again (or exits), so the long-lived @conn never would.
        reader = PG.connect(url)
        reader.exec("SET enable_seqscan = off; SELECT count(*) FROM sr_events WHERE kind = 'k1'")
        reader.close
      end

      after(:all) { @conn&.exec("DROP TABLE IF EXISTS sr_events, sr_fk_parent, sr_fk_child, sr_cyc CASCADE") }

      let(:db) { described_class.new(db_url).call }

      it "reports a partitioned table once, with rows summed from its partitions" do
        names = db.tables.map(&:name)
        expect(names).to include("sr_events")
        expect(names).not_to include("sr_events_2026_01", "sr_events_2026_02")
        expect(db.table("sr_events").row_count).to be_within(50).of(1000)
      end

      it "counts a partitioned index's scans across its partitions" do
        # pg_stat counters are flushed asynchronously; give them a moment
        idx = nil
        10.times do
          idx = described_class.new(db_url).call.table("sr_events").indexes.find { |i| i.name == "idx_sr_events_kind" }
          break if idx.scans.to_i.positive?

          sleep 0.5
        end
        expect(idx.scans).to be_positive
      end

      it "treats same-column FKs with different ON DELETE as different constraints" do
        fks = db.table("sr_fk_child").foreign_key_constraints.to_h { |fk| [fk.name, fk.behaviour] }
        expect(fks["fk_a"]).to eq(fks["fk_c"])
        expect(fks["fk_a"]).not_to eq(fks["fk_b"])

        findings = SchemaReaper::Analyzers::DuplicateForeignKey.new(context_for(schema: db)).call
        expect(findings.map(&:index)).to eq(["fk_c"])
      end

      it "skips a CYCLE sequence, which wraps instead of running out" do
        expect(db.sequences.map(&:table)).not_to include("sr_cyc")
      end

      it "scales column bytes by the share of non-null rows" do
        # analysed table from the top-level setup: sometimes_null is ~50% NULL, 'y' = 2 bytes
        col = described_class.new(db_url).call.table("schema_reaper_analysed").column("sometimes_null")
        expect(col.bytes).to eq(1)
      end
    end
  end
end
