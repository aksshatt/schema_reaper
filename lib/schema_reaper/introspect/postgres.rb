# frozen_string_literal: true

module SchemaReaper
  module Introspect
    # Reads live schema from a PostgreSQL database using the `pg` gem directly,
    # so the host app does not need to boot Rails.
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
        DatabaseSchema.new(tables: table_names.map { |n| build_table(n) })
      end

      private

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
          foreign_keys: foreign_keys_for(name)
        )
      end

      def columns_for(table)
        exec(<<~SQL, [table]).map do |r|
          SELECT column_name, data_type, is_nullable, column_default
          FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = $1
          ORDER BY ordinal_position
        SQL
          Column.new(
            name: r["column_name"],
            sql_type: r["data_type"],
            null: r["is_nullable"] == "YES",
            default: r["column_default"],
            bytes: AVG_TYPE_BYTES.fetch(r["data_type"], 16)
          )
        end
      end

      def indexes_for(table)
        exec(<<~SQL, [table]).map do |r|
          SELECT i.relname AS name, ix.indisunique AS unique,
                 array_to_string(array_agg(a.attname ORDER BY a.attnum), ',') AS cols
          FROM pg_class t
          JOIN pg_index ix ON t.oid = ix.indrelid
          JOIN pg_class i ON i.oid = ix.indexrelid
          JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
          WHERE t.relname = $1
          GROUP BY i.relname, ix.indisunique
        SQL
          Index.new(name: r["name"], columns: r["cols"].split(","), unique: r["unique"] == "t")
        end
      end

      def primary_key_for(table)
        exec(<<~SQL, [table]).map { |r| r["attname"] }.first
          SELECT a.attname
          FROM pg_index i
          JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
          WHERE i.indrelid = $1::regclass AND i.indisprimary
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

      def exec(sql, params = nil)
        (params ? @conn.exec_params(sql, params) : @conn.exec(sql)).to_a
      end
    end
  end
end
