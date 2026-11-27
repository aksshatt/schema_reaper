# frozen_string_literal: true

module SchemaReaper
  # Finds the line in db/schema.rb (or db/structure.sql) that defines a
  # finding's table, column or index, so SARIF annotations land on it instead
  # of line 1 of a file that may not even exist.
  class SchemaLocator
    Location = Struct.new(:path, :line, keyword_init: true)

    CANDIDATES = %w[db/schema.rb db/structure.sql].freeze

    def initialize(root: Dir.pwd)
      @root = root
      @path = CANDIDATES.find { |p| File.exist?(File.join(root, p)) }
      @lines = @path ? File.readlines(File.join(root, @path)) : []
    end

    # @return [Location, nil] nil when there is no schema file at all
    def locate(finding)
      return nil unless @path

      Location.new(path: @path, line: line_for(finding) || 1)
    end

    private

    def line_for(finding)
      start = table_line(finding.table)
      return nil unless start

      block = block_after(start)
      found = (finding.index && (find_in(block, quoted(finding.index)) || find_in(all_lines, quoted(finding.index)))) ||
              (finding.column && find_in(block, column_pattern(finding.column.split(",").first)))
      found || (start + 1)
    end

    # schema.rb:     create_table "users", ...      (schema-qualified: "billing.users")
    # structure.sql: CREATE TABLE public.users (
    def table_line(table)
      bare = table.split(".").last
      ns = table.include?(".") ? table.split(".").first : "public"
      rb = /create_table\s+"#{Regexp.escape(table)}"/
      sql = /CREATE TABLE (?:"?#{Regexp.escape(ns)}"?\.)?"?#{Regexp.escape(bare)}"?\s*\(/
      @lines.index { |l| l.match?(rb) || l.match?(sql) }
    end

    # Lines from the table's definition to the next table, as [text, index]
    # pairs. Indexes in schema.rb sit inside the block; in structure.sql they
    # come later as CREATE INDEX name ON ..., hence the whole-file fallback
    # for an index (index names are unique per schema, so it can't mismatch).
    def block_after(start)
      rest = all_lines.drop(start + 1)
      stop = rest.index { |l, _| l.match?(/\A\s*create_table\s|\ACREATE TABLE /) }
      stop ? rest.first(stop) : rest
    end

    def all_lines
      @all_lines ||= @lines.each_with_index.to_a
    end

    def find_in(pairs, pattern)
      hit = pairs.find { |l, _| l.match?(pattern) }
      hit && (hit[1] + 1)
    end

    def quoted(name)
      /["\s]#{Regexp.escape(name)}["\s]/
    end

    # schema.rb: t.string "email"    structure.sql:     email character varying
    def column_pattern(column)
      /\A\s*(?:t\.\w+\s+"#{Regexp.escape(column)}"|"?#{Regexp.escape(column)}"?\s+\w)/
    end
  end
end
