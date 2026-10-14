# frozen_string_literal: true

# Fixture for spec/static/scoped_scan_spec.rb.
class LineItem < ApplicationRecord
  self.table_name = "order_lines"
end
