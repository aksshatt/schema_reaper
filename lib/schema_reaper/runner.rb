# frozen_string_literal: true

module SchemaReaper
  # Ties introspection + scanning + analyzers together and returns findings.
  class Runner
    def initialize(config: Config.load, root: Dir.pwd, introspector: nil)
      @config = config
      @root = root
      @introspector = introspector
    end

    def run
      ctx = Analyzers::Context.new(
        schema: schema,
        used_tokens: Static::Scanner.new(@config, root: @root).call,
        config: @config
      )

      Analyzers::Registry.all.flat_map { |klass| klass.new(ctx).call }
    end

    private

    def schema
      return @introspector.call if @introspector

      Introspect::Postgres.new(@config.database_url).call
    end
  end
end
