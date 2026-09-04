# frozen_string_literal: true

module SchemaReaper
  module Analyzers
    # Analyzers register themselves here so the runner can iterate them.
    module Registry
      @classes = []

      class << self
        attr_reader :classes

        def register(klass)
          @classes << klass unless @classes.include?(klass)
        end

        def all = @classes
      end
    end
  end
end
