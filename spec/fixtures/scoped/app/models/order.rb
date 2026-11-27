# frozen_string_literal: true

# Fixture for spec/static/scoped_scan_spec.rb.
class Order < ApplicationRecord
  belongs_to :user

  def shipped?
    status == "shipped" && user.nickname.present?
  end
end
