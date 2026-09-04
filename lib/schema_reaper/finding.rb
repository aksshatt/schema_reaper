# frozen_string_literal: true

module SchemaReaper
  # A single issue reported by an analyzer.
  Finding = Struct.new(
    :type,              # Symbol, e.g. :dead_column
    :table,             # String
    :column,            # String or nil
    :index,             # String or nil (index name, for index findings)
    :severity,          # :low | :medium | :high
    :confidence,        # 0.0..1.0
    :bytes_per_row,     # Integer estimate, 0 if unknown
    :reclaimable_bytes, # Integer, bytes_per_row * row_count
    :evidence,          # Array<String> human-readable reasons
    :suggested_fix,     # String
    keyword_init: true
  ) do
    def id
      [type, table, column, index].compact.join("/")
    end

    def reclaimable_bytes
      self[:reclaimable_bytes] || 0
    end

    def to_h
      super.merge(id: id, reclaimable_bytes: reclaimable_bytes)
    end
  end
end
