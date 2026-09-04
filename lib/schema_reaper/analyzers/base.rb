# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # Context passed to every analyzer's #call.
    Context = Struct.new(:schema, :used_tokens, :config, keyword_init: true)

    # Shared plumbing for analyzers: schema access and token lookup helpers.
    class Base
      def self.type = name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym

      def initialize(context)
        @ctx = context
      end

      # @return [Array<Finding>]
      def call = raise NotImplementedError

      private

      attr_reader :ctx

      def schema = ctx.schema
      def used?(token) = ctx.used_tokens.include?(token.to_s.downcase)
      def config = ctx.config
    end
  end
end
