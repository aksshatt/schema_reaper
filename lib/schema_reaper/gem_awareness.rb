# frozen_string_literal: true

require "set"

module SchemaReaper
  # Columns and tables that popular gems own and reference indirectly (through
  # metaprogramming the static scanner cannot see). Detected gems get their
  # columns whitelisted automatically.
  module GemAwareness
    # gem name => { table_glob => [column names] }.  "*" table_glob matches any
    # table; an exact name matches only that table.
    MAP = {
      "devise" => { "*" => %w[
        encrypted_password reset_password_token reset_password_sent_at
        remember_created_at sign_in_count current_sign_in_at last_sign_in_at
        current_sign_in_ip last_sign_in_ip confirmation_token confirmed_at
        confirmation_sent_at unconfirmed_email failed_attempts unlock_token
        locked_at provider uid
      ] },
      "paper_trail" => { "versions" => %w[item_type item_id event whodunnit object object_changes] },
      "audited" => { "audits" => %w[auditable_type auditable_id user_type user_id action audited_changes version] },
      "friendly_id" => { "friendly_id_slugs" => %w[slug sluggable_id sluggable_type scope] },
      "acts_as_paranoid" => { "*" => %w[deleted_at] },
      "paranoia" => { "*" => %w[deleted_at] },
      "counter_culture" => { "*" => %w[] }, # dynamic *_count columns handled by regex in config
      "activestorage" => {
        "active_storage_blobs" => %w[key filename content_type metadata service_name byte_size checksum],
        "active_storage_attachments" => %w[name record_type record_id blob_id],
        "active_storage_variant_records" => %w[blob_id variation_digest]
      },
      "actiontext" => { "action_text_rich_texts" => %w[body record_type record_id name] },
      "pg_search" => { "pg_search_documents" => %w[content searchable_type searchable_id] },
      "ahoy_matey" => {
        "ahoy_visits" => %w[visit_token visitor_token],
        "ahoy_events" => %w[visit_id name properties]
      }
    }.freeze

    # @param installed [Enumerable<String>] gem names present in the bundle
    # @param tables [Enumerable<#name,#column_names>] or Enumerable<String>
    # @return [Hash{String => Set<String>}]
    #
    # For an exact table_glob the columns are reserved on that table. For "*"
    # (columns a gem can add to any model table) they are reserved only on
    # tables that already contain the first ("anchor") column of the list, so an
    # unrelated `provider`/`uid` column elsewhere is still reportable.
    def self.reserved_columns(installed:, tables:)
      installed = installed.to_set
      index = tables.to_h { |t| t.respond_to?(:name) ? [t.name, t.column_names] : [t, nil] }
      result = Hash.new { |h, k| h[k] = Set.new }

      MAP.each do |gem_name, table_map|
        next unless installed.include?(gem_name)

        table_map.each do |table_glob, columns|
          next if columns.empty?

          if table_glob == "*"
            anchor = columns.first
            index.each do |name, cols|
              result[name].merge(columns) if cols&.include?(anchor)
            end
          elsif index.key?(table_glob)
            result[table_glob].merge(columns)
          end
        end
      end
      result
    end

    # Best-effort list of gems in the current bundle.
    def self.installed_gems
      if defined?(Bundler)
        Bundler.load.specs.map(&:name)
      else
        Gem::Specification.map(&:name)
      end
    rescue StandardError
      []
    end
  end
end
