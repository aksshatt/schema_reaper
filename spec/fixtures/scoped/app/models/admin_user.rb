# frozen_string_literal: true

# Fixture: STI subclass of User.
class AdminUser < User
  def badge
    nickname
  end
end
