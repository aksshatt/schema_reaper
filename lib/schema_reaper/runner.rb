# frozen_string_literal: true

module SchemaReaper
  # Ties introspection + scanning + runtime data + analyzers together.
  class Runner
    def initialize(config: Config.load, root: Dir.pwd, introspector: nil, runtime: nil)
      @config = config
      @root = root
      @introspector = introspector
      @runtime = runtime
      load_plugins
    end

    def run
      db = schema
      ctx = Analyzers::Context.new(
        schema: db,
        used_tokens: Static::Scanner.new(@config, root: @root).call,
        runtime: runtime_report,
        gem_columns: gem_columns(db),
        config: @config
      )

      findings = Analyzers::Registry.all.flat_map { |klass| klass.new(ctx).call }
      dedupe(findings).sort_by { |f| [-f.confidence, f.id] }
    end

    private

    # When a whole table is dead, its per-column and per-index findings are
    # noise -- keep only the table-level finding for that table.
    def dedupe(findings)
      dead_tables = findings.select { |f| f.type == :dead_table }.to_set(&:table)
      findings.reject { |f| f.type != :dead_table && dead_tables.include?(f.table) }
    end

    def schema
      return @introspector.call if @introspector

      Introspect::Postgres.new(@config.database_url).call
    end

    def runtime_report
      return @runtime if @runtime

      Runtime::Report.load(@config.runtime_log)
    end

    def gem_columns(db)
      return {} unless @config.gem_awareness?

      GemAwareness.reserved_columns(
        installed: GemAwareness.installed_gems,
        tables: db.tables
      )
    end

    def load_plugins
      @config.require_paths.each do |path|
        require(File.expand_path(path, @root))
      end
    end
  end
end
