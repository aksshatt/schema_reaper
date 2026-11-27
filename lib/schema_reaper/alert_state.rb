# frozen_string_literal: true

module SchemaReaper
  # Remembers which finding ids the last delivered report contained, so the
  # next one can say what changed -- and, with alert_on: :changes, stay quiet
  # when nothing did. Kept in Rails.cache (the manual trigger's cooldown
  # already relies on it) because production filesystems are often
  # ephemeral. Without a cache every report is treated as the first.
  class AlertState
    KEY = "schema_reaper:last_alert_ids"

    def initialize(cache: default_cache)
      @cache = cache
    end

    # @return [Array<String>, nil] nil when no earlier report is known
    def previous_ids
      @cache&.read(KEY)
    rescue StandardError
      nil
    end

    def remember(ids)
      @cache&.write(KEY, ids.sort)
    rescue StandardError
      nil
    end

    private

    def default_cache
      defined?(Rails) && Rails.respond_to?(:cache) ? Rails.cache : nil
    end
  end
end
