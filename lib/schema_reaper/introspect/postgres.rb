# frozen_string_literal: true

module SchemaReaper
  module Introspect
    # Reads live schema + planner statistics from PostgreSQL using the `pg` gem
    # directly, so the host app does not need to boot Rails.
    class Postgres
      AVG_TYPE_BYTES = {
        "boolean" => 1, "smallint" => 2, "integer" => 4, "bigint" => 8,
        "real" => 4, "double precision" => 8, "numeric" => 8,
        "date" => 4, "timestamp without time zone" => 8,
        "timestamp with time zone" => 8, "uuid" => 16
      }.freeze

      def initialize(url)
        raise Error, "no database_url configured" if url.nil? || url.empty?

        require "pg"
        @conn = PG.connect(url)
      end

      def call
        DatabaseSchema.new(
          tables: table_names.map { |n| build_table(n) },
          index_scan_total: index_scan_total
        )
      end

      private

      # Cluster-wide cumulative index scans. Lets the unused-index analyzer tell
      # "this index is never used" apart from "this database has no query
      # history", which look identical at the level of a single idx_scan = 0.
      def index_scan_total
        exec("SELECT COALESCE(sum(idx_scan), 0) AS total FROM pg_stat_user_indexes")
          .first&.fetch("total")&.to_i
      end

      def table_names
        exec(<<~SQL).map { |r| r["tablename"] }
          SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename
        SQL
      end

      def build_table(name)
        Table.new(
          name: name,
          columns: columns_for(name),
          indexes: indexes_for(name),
          primary_key: primary_key_for(name),
          foreign_keys: foreign_keys_for(name),
          row_count: row_count_for(name)
        )
      end

      def columns_for(table)
        stats = column_stats_for(table)
        exec(<<~SQL, [table]).map do |r|
          SELECT column_name, data_type, is_nullable, column_default
          FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = $1
          ORDER BY ordinal_position
        SQL
          s = stats[r["column_name"]] || {}
          Column.new(
            name: r["column_name"],
            sql_type: r["data_type"],
            null: r["is_nullable"] == "YES",
            default: r["column_default"],
            bytes: AVG_TYPE_BYTES.fetch(r["data_type"], 16),
            null_fraction: s[:null_frac],
            distinct_values: s[:n_distinct]
          )
        end
      end

      # pg_stats.n_distinct: >= 0 is an absolute count, < 0 is a ratio of rows.
      def column_stats_for(table)
        exec(<<~SQL, [table]).each_with_object({}) do |r, h|
          SELECT attname, null_frac, n_distinct
          FROM pg_stats WHERE schemaname = 'public' AND tablename = $1
        SQL
          nd = r["n_distinct"].to_f
          h[r["attname"]] = {
            null_frac: r["null_frac"].to_f,
            n_distinct: nd >= 0 ? nd.round : nil
          }
        end
      end

      # Columns must come back in index-key order, not table order: prefix
      # comparisons (Index#covers?) are only meaningful on the real key order.
      # unnest(indkey) WITH ORDINALITY preserves that; ORDER BY attnum does not.
      def indexes_for(table)
        exec(<<~SQL, [table]).map do |r|
          SELECT i.relname AS name, ix.indisunique AS "unique", ix.indisprimary AS "primary",
                 s.idx_scan AS scans,
                 array_to_string(array_agg(a.attname ORDER BY k.ord), ',') AS cols
          FROM pg_class t
          JOIN pg_index ix ON t.oid = ix.indrelid
          JOIN pg_class i ON i.oid = ix.indexrelid
          JOIN LATERAL unnest(ix.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord) ON TRUE
          JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
          LEFT JOIN pg_stat_user_indexes s ON s.indexrelid = i.oid
          WHERE t.relname = $1
          GROUP BY i.relname, ix.indisunique, ix.indisprimary, s.idx_scan
        SQL
          Index.new(
            name: r["name"], columns: r["cols"].split(","),
            unique: r["unique"] == "t", primary: r["primary"] == "t",
            scans: r["scans"]&.to_i
          )
        end
      end

      # Every primary-key column, in key order. A composite key needs the whole
      # list: returning one arbitrary column leaves the rest looking like
      # ordinary columns to the analyzers.
      def primary_key_for(table)
        exec(<<~SQL, [table]).map { |r| r["attname"] }
          SELECT a.attname
          FROM pg_index i
          JOIN LATERAL unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord) ON TRUE
          JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
          WHERE i.indrelid = $1::regclass AND i.indisprimary
          ORDER BY k.ord
        SQL
      rescue PG::Error
        nil
      end

      def foreign_keys_for(table)
        exec(<<~SQL, [table]).map { |r| r["column_name"] }
          SELECT kcu.column_name
          FROM information_schema.table_constraints tc
          JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
          WHERE tc.constraint_type = 'FOREIGN KEY'
            AND tc.table_schema = 'public' AND tc.table_name = $1
        SQL
      end

      def row_count_for(table)
        exec(<<~SQL, [table]).first&.fetch("reltuples")&.to_f&.round
          SELECT reltuples FROM pg_class WHERE relname = $1
        SQL
      end

      def exec(sql, params = nil)
        (params ? @conn.exec_params(sql, params) : @conn.exec(sql)).to_a
      end
    end
  end
end
