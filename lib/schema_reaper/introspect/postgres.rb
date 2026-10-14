# frozen_string_literal: true

module SchemaReaper
  # Reads a live database's schema and statistics. PostgreSQL only for now.
  module Introspect
    # `pg` is deliberately not a runtime dependency -- the host app already
    # bundles its own (every Rails + PostgreSQL app does), and pinning a second
    # version here would fight it. Without this rescue a missing gem surfaces
    # as a baffling NameError instead.
    def self.require_pg!
      require "pg"
    rescue LoadError
      raise Error, "schema_reaper needs the `pg` gem to talk to PostgreSQL -- add `gem \"pg\"` to your Gemfile"
    end

    # Reads live schema + planner statistics from PostgreSQL using the `pg` gem
    # directly, so the host app does not need to boot Rails.
    class Postgres
      AVG_TYPE_BYTES = {
        "boolean" => 1, "smallint" => 2, "integer" => 4, "bigint" => 8,
        "real" => 4, "double precision" => 8, "numeric" => 8,
        "date" => 4, "timestamp without time zone" => 8, "timestamp with time zone" => 8, "uuid" => 16
      }.freeze

      NO_URL = "no database connection found. schema_reaper looks, in order, for: " \
               "database_url: in .schema_reaper.yml; the DATABASE_URL env var; config/database.yml " \
               "for RAILS_ENV (default: development, Postgres only)."

      # A record separator that cannot appear inside a plain identifier and is
      # exceedingly unlikely inside an expression, so splitting the aggregated
      # column list back apart in Ruby cannot be fooled by a comma the
      # expression itself contains: COALESCE(a, b), ROUND(x, 2), etc.
      COLUMN_SEPARATOR = 31.chr

      # Ceiling of each integer column type, for the sequence-exhaustion check:
      # a bigint sequence feeding an integer column overflows at the column's
      # limit, not the sequence's.
      TYPE_MAX = {
        "smallint" => 32_767, "integer" => 2_147_483_647, "bigint" => 9_223_372_036_854_775_807
      }.freeze

      # Tables in `public` keep their bare name, so every existing config,
      # baseline and finding id stays valid; tables in any other scanned schema
      # are reported as `schema.table`.
      def self.display_name(namespace, table)
        namespace == "public" ? table : "#{namespace}.#{table}"
      end

      def initialize(url, schemas: Config::DEFAULTS["schemas"])
        Introspect.require_pg!
        raise Error, NO_URL if url.nil? || url.empty?

        @schemas = Array(schemas)
        @conn = connect(url)
      end

      def call
        DatabaseSchema.new(
          tables: table_refs.map { |ns, name| build_table(ns, name) },
          index_scan_total: index_scan_total,
          sequences: sequences
        )
      end

      # Health facts for `schema_reaper doctor`, separate from #call so a scan
      # never pays for them.
      def diagnostics
        {
          server_version: exec("SHOW server_version").first&.fetch("server_version"),
          stats_reset: exec(<<~SQL).first&.fetch("stats_reset"),
            SELECT stats_reset FROM pg_stat_database WHERE datname = current_database()
          SQL
          never_analyzed: never_analyzed,
          in_recovery: exec("SELECT pg_is_in_recovery() AS r").first&.fetch("r") == "t"
        }
      end

      private

      def never_analyzed
        exec(<<~SQL, [pg_array(@schemas)]).map { |r| self.class.display_name(r["schemaname"], r["relname"]) }
          SELECT schemaname, relname FROM pg_stat_user_tables
          WHERE schemaname = ANY($1::text[]) AND last_analyze IS NULL AND last_autoanalyze IS NULL
          ORDER BY schemaname, relname
        SQL
      end

      # Kept out of #initialize: a `rescue PG::Error` there is evaluated for
      # *any* exception, including require_pg!'s, and would itself raise NameError
      # when pg is the thing that failed to load.
      def connect(url)
        PG.connect(url)
      rescue PG::Error => e
        raise Error, "could not connect to the database: #{e.message.strip}"
      end

      # Cluster-wide cumulative index scans. Lets the unused-index analyzer tell
      # "this index is never used" apart from "this database has no query
      # history", which look identical at the level of a single idx_scan = 0.
      def index_scan_total
        exec("SELECT COALESCE(sum(idx_scan), 0) AS total FROM pg_stat_user_indexes")
          .first&.fetch("total")&.to_i
      end

      # Partitions are left out: the app (and every analyzer) deals with the
      # partitioned parent, so reporting `events_2026_01` as an unreferenced
      # table would be wrong. The parent's row count and index usage are
      # rolled up from its partitions instead.
      def table_refs
        exec(<<~SQL, [pg_array(@schemas)]).map { |r| [r["schemaname"], r["tablename"]] }
          SELECT n.nspname AS schemaname, c.relname AS tablename
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE c.relkind IN ('r', 'p') AND NOT c.relispartition AND n.nspname = ANY($1::text[])
          ORDER BY n.nspname = 'public' DESC, n.nspname, c.relname
        SQL
      end

      def build_table(namespace, name)
        fks = foreign_key_constraints_for(namespace, name)
        Table.new(
          name: self.class.display_name(namespace, name),
          columns: columns_for(namespace, name),
          indexes: indexes_for(namespace, name),
          primary_key: primary_key_for(namespace, name),
          foreign_keys: fks.flat_map(&:columns).uniq,
          foreign_key_constraints: fks,
          row_count: row_count_for(namespace, name)
        )
      end

      def columns_for(namespace, table)
        stats = column_stats_for(namespace, table)
        exec(<<~SQL, [namespace, table]).map do |r|
          SELECT column_name, data_type, is_nullable, column_default
          FROM information_schema.columns
          WHERE table_schema = $1 AND table_name = $2
          ORDER BY ordinal_position
        SQL
          s = stats[r["column_name"]] || {}
          Column.new(
            name: r["column_name"],
            sql_type: r["data_type"],
            null: r["is_nullable"] == "YES",
            default: r["column_default"],
            bytes: measured_bytes(s) || AVG_TYPE_BYTES.fetch(r["data_type"], 16),
            null_fraction: s[:null_frac],
            distinct_values: s[:n_distinct]
          )
        end
      end

      # avg_width covers non-null values only, and a NULL takes no space in
      # the row (just its bit in the null bitmap), so scale by the share of
      # rows that actually hold a value.
      def measured_bytes(stats)
        return nil unless stats[:avg_width]

        (stats[:avg_width] * (1.0 - stats[:null_frac].to_f)).round
      end

      # pg_stats.n_distinct: >= 0 is an absolute count, < 0 is a ratio of rows.
      # avg_width is the measured average stored width of the non-null values,
      # far closer to reality than a per-type guess for text/jsonb/arrays.
      def column_stats_for(namespace, table)
        exec(<<~SQL, [namespace, table]).each_with_object({}) do |r, h|
          SELECT attname, null_frac, n_distinct, avg_width
          FROM pg_stats WHERE schemaname = $1 AND tablename = $2
          -- later rows win below: a plain row (inherited = false) beats an inherited one, and a
          -- partitioned parent, which only has inherited rows, still gets those
          ORDER BY inherited DESC
        SQL
          nd = r["n_distinct"].to_f
          width = r["avg_width"]&.to_i
          h[r["attname"]] = {
            null_frac: r["null_frac"].to_f,
            n_distinct: nd >= 0 ? nd.round : nil,
            avg_width: width&.positive? ? width : nil
          }
        end
      end

      # A partitioned parent's index (relkind 'I') is never scanned itself --
      # the planner scans each partition's index -- so its usage is the sum
      # over the leaf partitions, or every such index would look unused.
      #
      # Columns come back in index-key order via pg_get_indexdef(indexrelid,
      # column_no, pretty), keyed by column position rather than table attnum
      # so it renders a plain column and an expression uniformly and never
      # silently drops one. indnkeyatts excludes INCLUDE columns, which are
      # payload only. partial (indpred IS NOT NULL) lets analyzers refuse to
      # treat a conditional index as if it covered every row.
      def indexes_for(namespace, table)
        exec(<<~SQL, [namespace, table]).map do |r|
          SELECT i.relname AS name, ix.indisunique AS "unique", ix.indisprimary AS "primary",
                 (ix.indpred IS NOT NULL) AS partial,
                 #{partitioned_index_scans_sql} AS scans,
                 array_to_string(
                   array_agg(pg_get_indexdef(ix.indexrelid, k.ord::int, true) ORDER BY k.ord),
                   '#{COLUMN_SEPARATOR}'
                 ) AS cols
          FROM pg_class t
          JOIN pg_index ix ON t.oid = ix.indrelid
          JOIN pg_class i ON i.oid = ix.indexrelid
          JOIN LATERAL generate_series(1, ix.indnkeyatts) AS k(ord) ON TRUE
          LEFT JOIN pg_stat_user_indexes s ON s.indexrelid = i.oid
          WHERE t.relnamespace = $1::regnamespace AND t.relname = $2
          GROUP BY i.oid, i.relname, i.relkind, ix.indisunique, ix.indisprimary, ix.indpred, s.idx_scan
        SQL
          Index.new(
            name: r["name"], columns: r["cols"].split(COLUMN_SEPARATOR),
            unique: r["unique"] == "t", primary: r["primary"] == "t", partial: r["partial"] == "t",
            scans: r["scans"]&.to_i
          )
        end
      end

      # Every primary-key column, in key order. A composite key needs the whole
      # list: returning one arbitrary column leaves the rest looking like
      # ordinary columns to the analyzers. The relation is resolved by schema
      # and name rather than a ::regclass cast, which would follow search_path.
      def primary_key_for(namespace, table)
        exec(<<~SQL, [namespace, table]).map { |r| r["attname"] }
          SELECT a.attname
          FROM pg_index i
          JOIN pg_class t ON t.oid = i.indrelid
          JOIN LATERAL unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord) ON TRUE
          JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
          WHERE t.relnamespace = $1::regnamespace AND t.relname = $2 AND i.indisprimary
          ORDER BY k.ord
        SQL
      rescue Error, PG::Error
        nil
      end

      # Read from pg_constraint rather than information_schema: constraint
      # names are only unique per table, so joining key_column_usage on the
      # name alone mixes up two tables' same-named constraints. conkey keeps
      # a composite key's columns together and in order.
      def foreign_key_constraints_for(namespace, table)
        exec(<<~SQL, [namespace, table]).map { |r| build_foreign_key(r) }
          SELECT c.conname AS name,
                 array_to_string(array_agg(a.attname ORDER BY k.ord), ',') AS cols,
                 rn.nspname AS ref_schema, rt.relname AS ref_table,
                 c.confkey::text AS ref_key, c.confupdtype, c.confdeltype, c.confmatchtype,
                 c.condeferrable, c.condeferred, c.convalidated
          FROM pg_constraint c
          JOIN pg_class t ON t.oid = c.conrelid
          JOIN pg_class rt ON rt.oid = c.confrelid
          JOIN pg_namespace rn ON rn.oid = rt.relnamespace
          JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord) ON TRUE
          JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
          WHERE c.contype = 'f' AND t.relnamespace = $1::regnamespace AND t.relname = $2
            #{"AND c.conparentid = 0" if version_num >= 110_000}
          GROUP BY c.conname, rn.nspname, rt.relname, c.confkey, c.confupdtype, c.confdeltype,
                   c.confmatchtype, c.condeferrable, c.condeferred, c.convalidated
          ORDER BY c.conname
        SQL
      end

      def build_foreign_key(row)
        ForeignKey.new(
          name: row["name"], columns: row["cols"].split(","),
          references: self.class.display_name(row["ref_schema"], row["ref_table"]),
          # Everything that changes what the constraint does. Two FKs are
          # only interchangeable when all of it matches.
          behaviour: [row["ref_key"], row["confupdtype"], row["confdeltype"], row["confmatchtype"],
                      row["condeferrable"], row["condeferred"]].join(":"),
          validated: row["convalidated"] == "t"
        )
      end

      # pg_class.reltuples is an estimate maintained by ANALYZE/VACUUM. On
      # PostgreSQL 14+ it is -1 for a relation that has never been analysed,
      # which is "unknown", not "minus one row". Map anything negative to nil so
      # analyzers treat the count as unavailable.
      # A partitioned parent holds no rows itself: sum its leaf partitions,
      # and treat the count as unknown if any leaf is unanalysed.
      def row_count_for(namespace, table)
        return legacy_row_count_for(namespace, table) unless pg12?

        rows = exec(<<~SQL, [namespace, table])
          SELECT leaf.reltuples
          FROM pg_class t
          JOIN LATERAL (
            SELECT c.reltuples FROM pg_partition_tree(t.oid) pt JOIN pg_class c ON c.oid = pt.relid
            WHERE t.relkind = 'p' AND pt.isleaf
            UNION ALL
            SELECT t.reltuples WHERE t.relkind = 'r'
          ) leaf ON TRUE
          WHERE t.relnamespace = $1::regnamespace AND t.relname = $2
        SQL
        counts = rows.map { |r| r["reltuples"].to_f }
        return nil if counts.empty? || counts.any?(&:negative?)

        counts.sum.round
      end

      # A CYCLE sequence wraps instead of running out, and a descending one
      # counts towards min_value, so neither is reported.
      #
      # Sequences owned by a column (serial, bigserial or IDENTITY), with the
      # ceiling that actually applies: the lower of the sequence's max_value
      # and the owning column type's. pg_sequences.last_value is NULL until
      # the sequence has been used, and unreadable without USAGE/SELECT on it.
      def sequences
        exec(<<~SQL, [pg_array(@schemas)]).map { |r| build_sequence(r) }
          SELECT s.schemaname, s.sequencename, s.last_value, s.max_value, s.min_value,
                 tn.nspname AS table_schema, t.relname AS table_name, a.attname AS column_name,
                 format_type(a.atttypid, NULL) AS column_type
          FROM pg_sequences s
          JOIN pg_class sc ON sc.relname = s.sequencename AND sc.relnamespace = s.schemaname::regnamespace
          JOIN pg_depend d ON d.objid = sc.oid AND d.classid = 'pg_class'::regclass
                          AND d.refclassid = 'pg_class'::regclass AND d.deptype IN ('a', 'i')
          JOIN pg_class t ON t.oid = d.refobjid
          JOIN pg_namespace tn ON tn.oid = t.relnamespace
          JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
          WHERE s.schemaname = ANY($1::text[]) AND s.last_value IS NOT NULL
            AND NOT s.cycle AND s.increment_by > 0
        SQL
      rescue Error
        [] # PG < 10 has no pg_sequences, or no privilege: skip, never fail the scan
      end

      def build_sequence(row)
        ceiling = [row["max_value"].to_i, TYPE_MAX.fetch(row["column_type"], row["max_value"].to_i)].min
        Sequence.new(
          name: self.class.display_name(row["schemaname"], row["sequencename"]),
          table: self.class.display_name(row["table_schema"], row["table_name"]),
          column: row["column_name"], column_type: row["column_type"],
          last_value: row["last_value"].to_i, max_value: ceiling
        )
      end

      # PostgreSQL 10/11 lack pg_partition_tree (and 10 lacks conparentid).
      # Both are still worth supporting; on them partitioned parents get the
      # pre-partition-aware treatment.
      def version_num
        @version_num ||= exec("SHOW server_version_num").first["server_version_num"].to_i
      end

      def pg12?
        version_num >= 120_000
      end

      def partitioned_index_scans_sql
        return "s.idx_scan" unless pg12?

        <<~SQL.strip
          CASE WHEN i.relkind = 'I' THEN (
            SELECT sum(cs.idx_scan) FROM pg_partition_tree(i.oid) pt
            JOIN pg_stat_user_indexes cs ON cs.indexrelid = pt.relid
            WHERE pt.isleaf
          ) ELSE s.idx_scan END
        SQL
      end

      def legacy_row_count_for(namespace, table)
        raw = exec(<<~SQL, [namespace, table]).first&.fetch("reltuples")&.to_f
          SELECT reltuples FROM pg_class WHERE relnamespace = $1::regnamespace AND relname = $2
        SQL
        raw.nil? || raw.negative? ? nil : raw.round
      end

      def pg_array(values)
        PG::TextEncoder::Array.new.encode(values)
      end

      def exec(sql, params = nil)
        (params ? @conn.exec_params(sql, params) : @conn.exec(sql)).to_a
      rescue PG::Error => e
        raise Error, "query against the database failed: #{e.message.strip}"
      end
    end
  end
end
