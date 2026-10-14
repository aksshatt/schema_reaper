# frozen_string_literal: true

require "set"

module SchemaReaper
  # Ties introspection + scanning + runtime data + analyzers together.
  class Runner
    SEVERITY_RANK = { high: 0, medium: 1, low: 2 }.freeze

    # only / except - analyzer type names (strings or symbols) to restrict the
    #                 run to, or to leave out. Unknown names raise Error.
    # min_confidence  - drop findings below this; defaults to the config key.
    def initialize(config: Config.load, root: Dir.pwd, introspector: nil, runtime: nil,
                   only: nil, except: nil, min_confidence: nil)
      @config = config
      @root = root
      @introspector = introspector
      @runtime = runtime
      @only = names(only)
      @except = names(except)
      @min_confidence = min_confidence || config.min_confidence
      load_plugins
    end

    def run
      selected = analyzers
      db = schema
      warn_missing_query_history(db) if selected.include?(Analyzers::UnusedIndex)
      scan = Static::Scanner.new(@config, root: @root).scan
      ctx = Analyzers::Context.new(
        schema: db,
        used_tokens: scan.tokens,
        scan: scan,
        runtime: runtime_report,
        gem_columns: gem_columns(db),
        gem_owned_tables: gem_owned_tables,
        config: @config
      )

      findings = selected.flat_map { |klass| klass.new(ctx).call }
      dedupe(kept_in_code(findings, scan.keeps)).select { |f| f.confidence >= @min_confidence }
                                                .sort_by do |f|
        [
          -f.confidence, f.id
        ]
      end
    end

    private

    # `# schema_reaper:keep TARGET` in code silences a finding. TARGET is a
    # column (any table), table.column, a table (every finding on it) or an
    # index name.
    def kept_in_code(findings, keeps)
      return findings if keeps.empty?

      findings.reject do |f|
        targets = [f.table, f.column, f.index, f.column && "#{f.table}.#{f.column}"].compact.map(&:downcase)
        targets.any? { |t| keeps.key?(t) }
      end
    end

    def names(list)
      list && Array(list).flat_map { |n| n.to_s.split(",") }.map { |n| n.strip.to_sym }.reject(&:empty?)
    end

    # Plugins load in #initialize, so the registry is complete by the time
    # the names are checked -- a custom analyzer can be selected like a core one.
    def analyzers
      all = Analyzers::Registry.all
      known = all.map(&:type)
      unknown = ((@only || []) + (@except || [])) - known
      raise Error, "unknown analyzer(s): #{unknown.join(", ")} (known: #{known.join(", ")})" if unknown.any?

      all.select { |k| @only.nil? || @only.include?(k.type) }
         .reject { |k| @except&.include?(k.type) }
    end

    # Silently reporting nothing would look like a clean bill of health, so say
    # why the unused-index analyzer sat this run out.
    def warn_missing_query_history(db)
      return if db.query_history?

      Reporters::Console.new.notice(
        "unused_index skipped — only #{db.index_scan_total} scan(s) across " \
        "#{db.index_count} indexes, so there is no query history to judge by. " \
        "Run against a database that has served production traffic."
      )
    end

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

      Introspect::Postgres.new(@config.database_url, schemas: @config.schemas).call
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

    def gem_owned_tables
      return Set.new unless @config.gem_awareness?

      GemAwareness.owned_tables(installed: GemAwareness.installed_gems)
    end

    def load_plugins
      @config.require_paths.each do |path|
        require(File.expand_path(path, @root))
      end
    end
  end
end
