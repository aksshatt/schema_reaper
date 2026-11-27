# frozen_string_literal: true

# Fixture: a second abstract base that models inherit from.
class LegacyRecord < ApplicationRecord
  self.abstract_class = true
end
