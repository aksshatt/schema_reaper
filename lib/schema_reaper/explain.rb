# frozen_string_literal: true

module SchemaReaper
  # `schema_reaper explain ID`: everything known about one finding, and the
  # exact command to act on it.
  class Explain
    def initialize(findings, config:, root: Dir.pwd, console: Reporters::Console.new)
      @findings = findings
      @config = config
      @root = root
      @console = console
    end

    # @return [Boolean] false when no finding matches
    def call(query)
      matches = match(query)
      if matches.size == 1
        render(matches.first)
      elsif matches.empty?
        report_not_found(query)
      else
        report_ambiguous(query, matches)
      end
      matches.size == 1
    end

    private

    # An exact id, else every finding whose id contains the query
    # ("users/legacy_token" finds dead_column/users/legacy_token).
    def match(query)
      exact = @findings.select { |f| f.id == query }
      exact.any? ? exact : @findings.select { |f| f.id.include?(query) }
    end

    def report_not_found(query)
      @console.problem("no current finding matches #{query.inspect}")
      table_finding = @findings.find { |f| f.type == :dead_table && query.split("/").include?(f.table) }
      if table_finding
        @console.info("its table is reported whole as #{table_finding.id} -- per-column and per-index " \
                      "findings on a dead table are folded into that one")
        return
      end

      @console.info("list them with `schema_reaper scan --format json` -- ids look like dead_column/users/legacy_token")
    end

    def report_ambiguous(query, matches)
      @console.problem("#{matches.size} findings match #{query.inspect} -- be more specific:",
                       items: matches.map(&:id))
    end

    def render(finding)
      @console.title("explain", finding.id)
      @console.row("type", finding.type)
      @console.row("severity", finding.severity)
      @console.row("confidence", format("%.2f", finding.confidence))
      @console.row("reclaimable", reclaim(finding))
      @console.row("defined at", location(finding)) if location(finding)
      @console.row("baseline", baseline_status(finding))
      @console.blank
      @console.list("evidence", finding.evidence, colour: :reset)
      @console.blank
      @console.list("fix", [finding.suggested_fix], colour: :reset)
      next_step = next_command(finding)
      @console.list("next", [next_step], colour: :reset) if next_step
    end

    def reclaim(finding)
      return "unknown (row count unavailable -- run ANALYZE)" unless finding.reclaim_known?

      Reporters::Bytes.human(finding.reclaimable_bytes)
    end

    def location(finding)
      @location ||= {}
      @location[finding.id] ||= begin
        loc = SchemaLocator.new(root: @root).locate(finding)
        loc && "#{loc.path}:#{loc.line}"
      end
    end

    def baseline_status(finding)
      entry = Baseline.new(@config.baseline_path).entries.find { |e| e.id == finding.id }
      return "not accepted (fails `scan --ci`)" unless entry
      return "accepted, but expired #{entry.expires_on}" if entry.expired?

      ["accepted", entry.reason, entry.expires_on && "until #{entry.expires_on}"].compact.join(" -- ")
    end

    def next_command(finding)
      case finding.type
      when :dead_column, :always_null_column, :single_value_column
        "bundle exec schema_reaper generate-migration #{finding.table} #{finding.column}"
      when :unused_index, :duplicate_index
        "bundle exec schema_reaper generate-migration #{finding.table} --index #{finding.index}"
      when :dead_table
        "bundle exec schema_reaper generate-migration #{finding.table}"
      end
    end
  end
end
