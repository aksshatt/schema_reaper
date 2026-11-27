# frozen_string_literal: true

# Fixture for spec/static/scoped_scan_spec.rb.
class User < ApplicationRecord
  # schema_reaper:keep legacy_token, users.api_key -- read by the billing ETL
  def label
    email
  end
end
