# frozen_string_literal: true

# Fixture for spec/static/scoped_scan_spec.rb.
class HomeController < ApplicationController
  def index
    @title = "welcome"
  end
end
