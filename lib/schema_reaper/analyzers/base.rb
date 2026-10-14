# frozen_string_literal: true

require "set"

module SchemaReaper
  module Analyzers
    # Context passed to every analyzer's #call.
    #   schema           - DatabaseSchema
    #   used_tokens      - Set<String> from the static scan
    #   runtime          - Runtime::Report (may be empty)
    #   gem_columns      - Hash{table_name => Set<column_name>} reserved by gems
    #   gem_owned_tables - Set<table_name> created and owned outright by a gem
    #   config           - Config
    #   scan             - Static::Result (optional; per-model detail
    #                      for column_scope: model)
    Context = Struct.new(:schema, :used_tokens, :runtime, :gem_columns, :gem_owned_tables, :config, :scan,
                         keyword_init: true) do
      def scan
        self[:scan] || Static::Result.from_tokens(used_tokens || [])
      end

      def runtime
        self[:runtime] || Runtime::Report.empty
      end

      def gem_columns
        self[:gem_columns] || {}
      end

      def gem_owned_tables
        self[:gem_owned_tables] || Set.new
      end
    end

    # Shared plumbing for analyzers: schema access and token lookup helpers.
    class Base
      # ANALYZE reads a sample of 300 x default_statistics_target rows (30,000
      # at the default of 100). Above that, pg_stats' null_frac and n_distinct
      # are estimates: a value held by a handful of rows can be missed.
      STATS_SAMPLE_ROWS = 30_000

      def self.type
        name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
      end

      def initialize(context)
        @ctx = context
      end

      # @return [Array<Finding>]
      def call
        raise(NotImplementedError)
      end

      private

      attr_reader :ctx

      def schema
        ctx.schema
      end

      def config
        ctx.config
      end

      def runtime
        ctx.runtime
      end

      def used?(token)
        ctx.used_tokens.include?(token.to_s.downcase)
      end

      # Whether code references `column` on `table`. With column_scope: model,
      # a name seen only in model files counts just for the tables those
      # models are, or mention (an association, a class name), so Order's
      # `status` no longer hides a dead `status` on users.
      def column_used?(table, column)
        return used?(column) unless config.column_scope == :model

        name = column.to_s.downcase
        scan = ctx.scan
        return true if scan.shared.include?(name)

        forms = table_forms(table)
        scan.models.any? do |model|
          model.tokens.include?(name) && (model.tables.include?(table) || forms.any? { |f| model.tokens.include?(f) })
        end
      end

      def table_forms(table)
        bare = table.to_s.split(".").last
        singular = Inflect.singularize(bare)
        [bare, singular, singular.delete("_")].uniq
      end

      # Every column of a table a gem owns outright is the gem's business.
      def gem_reserved?(table, column)
        gem_owned_table?(table) || ctx.gem_columns.fetch(table, []).include?(column)
      end

      def sampled_stats?(table)
        table.row_count.to_i > STATS_SAMPLE_ROWS
      end

      # The `ignore.columns` list (names or /regex/) applies to every
      # column-level analyzer, not only dead_column.
      def ignored_column?(name)
        config.ignored_column?(name)
      end

      # A table name as a Ruby symbol literal for suggested fixes: :users, or
      # :"billing.invoices" for a table outside the public schema.
      def sym(name)
        name.to_sym.inspect
      end

      def gem_owned_table?(table)
        ctx.gem_owned_tables.include?(table)
      end

      # Builds a Finding, filling in reclaimable_bytes from the row count.
      # An unknown row count leaves reclaimable_bytes nil: "we cannot say" is
      # not the same claim as "zero bytes", and reporters need to tell them
      # apart. Finding#reclaimable_bytes still reads 0 for arithmetic.
      def finding(table:, bytes_per_row: 0, row_count: nil, **rest)
        rows = row_count || schema.table(table)&.row_count
        Finding.new(
          table: table,
          bytes_per_row: bytes_per_row,
          reclaimable_bytes: rows && (bytes_per_row * rows),
          **rest
        )
      end
    end
  end
end
