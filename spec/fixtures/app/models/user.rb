# frozen_string_literal: true

# Fixture model used by scanner + analyzer specs.
class User < ApplicationRecord
  validates :email, presence: true

  scope :active, -> { where(state: "active") }

  def display_name
    [first_name, last_name].compact.join(" ")
  end

  def self.by_email(value)
    where("email = ?", value)
  end
end
