# frozen_string_literal: true

module SchemaReaper
  module Reporters
    # Formats a byte count as a human-readable size (e.g. "3.4 MB").
    module Bytes
      UNITS = %w[B KB MB GB TB].freeze

      module_function

      def human(n)
        n = n.to_f
        idx = 0
        while n >= 1024 && idx < UNITS.length - 1
          n /= 1024
          idx += 1
        end
        format("%.1f %s", n, UNITS[idx])
      end
    end
  end
end
