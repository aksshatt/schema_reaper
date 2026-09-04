# frozen_string_literal: true

module SchemaReaper
  # A single issue reported by an analyzer.
  Finding = Struct.new(
    :type,          # Symbol, e.g. :dead_column
    :table,         # String
    :column,        # String or nil
    :severity,      # :low | :medium | :high
    :confidence,    # 0.0..1.0
    :bytes_per_row, # Integer estimate, 0 if unknown
    :evidence,      # Array<String> human-readable reasons
    :suggested_fix, # String
    keyword_init: true
  ) do
    def id
      [type, table, column].compact.join("/")
    end

    def to_h
      super.merge(id: id)
    end
  end
end
