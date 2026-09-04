# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # Context passed to every analyzer's #call.
    #   schema       - DatabaseSchema
    #   used_tokens  - Set<String> from the static scan
    #   runtime      - Runtime::Report (may be empty)
    #   gem_columns  - Hash{table_name => Set<column_name>} reserved by gems
    #   config       - Config
    Context = Struct.new(:schema, :used_tokens, :runtime, :gem_columns, :config, keyword_init: true) do
      def runtime = self[:runtime] || Runtime::Report.empty
      def gem_columns = self[:gem_columns] || {}
    end

    # Shared plumbing for analyzers: schema access and token lookup helpers.
    class Base
      def self.type
        name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
      end

      def initialize(context)
        @ctx = context
      end

      # @return [Array<Finding>]
      def call = raise(NotImplementedError)

      private

      attr_reader :ctx

      def schema = ctx.schema
      def config = ctx.config
      def runtime = ctx.runtime
      def used?(token) = ctx.used_tokens.include?(token.to_s.downcase)

      def gem_reserved?(table, column)
        ctx.gem_columns.fetch(table, []).include?(column)
      end

      # Builds a Finding, filling in reclaimable_bytes from the row count.
      def finding(table:, bytes_per_row: 0, row_count: nil, **rest)
        rows = row_count || schema.table(table)&.row_count || 0
        Finding.new(
          table: table,
          bytes_per_row: bytes_per_row,
          reclaimable_bytes: bytes_per_row * rows,
          **rest
        )
      end
    end
  end
end
