# frozen_string_literal: true

# Fixture: a PORO that lives in app/models.
class ReportForm < Struct.new(:form_field) # rubocop:disable Style/StructInheritance
end
