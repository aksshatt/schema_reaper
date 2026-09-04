# frozen_string_literal: true

require "set"

module SchemaReaper
  # Ties introspection + scanning + runtime data + analyzers together.
  class Runner
    SEVERITY_RANK = { high: 0, medium: 1, low: 2 }.freeze

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

    def dedupe(findings)
      collapse_targets(drop_findings_on_dead_tables(findings))
    end

    # When a whole table is dead, its per-column and per-index findings are
    # noise -- keep only the table-level finding for that table.
    def drop_findings_on_dead_tables(findings)
      dead_tables = findings.select { |f| f.type == :dead_table }.to_set(&:table)
      findings.reject { |f| f.type != :dead_table && dead_tables.include?(f.table) }
    end

    # Several analyzers can flag the same physical column or index (e.g.
    # dead_column + always_null_column). Keep the highest-confidence finding per
    # target so it is reported -- and its bytes counted -- exactly once, but note
    # the other analyzers that agreed.
    def collapse_targets(findings)
      findings.group_by(&:target_key).map do |_key, group|
        winner = group.max_by { |f| [f.confidence, -SEVERITY_RANK.fetch(f.severity, 9)] }
        also = group.map(&:type).uniq - [winner.type]
        winner.evidence += ["also flagged by: #{also.join(", ")}"] if also.any?
        winner
      end
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
