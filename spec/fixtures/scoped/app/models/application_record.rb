# frozen_string_literal: true

# Fixture for spec/static/scoped_scan_spec.rb: abstract base.
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  def abstract_helper; end
end
