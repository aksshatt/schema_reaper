# frozen_string_literal: true

require "yaml"
require "erb"

module SchemaReaper
  # Best-effort resolution of a PostgreSQL connection URL from a Rails project,
  # so `schema_reaper scan` works in an app without `DATABASE_URL` exported or a
  # `database_url:` in .schema_reaper.yml.
  #
  # Order of preference is applied by Config; this module only handles the
  # config/database.yml case.
  module DatabaseUrl
    module_function

    POSTGRES_ADAPTERS = %w[postgresql postgis postgres].freeze

    # @return [String, nil]
    def from_rails(root: Dir.pwd, path: "config/database.yml", env: nil)
      file = File.expand_path(path, root)
      return nil unless File.file?(file)

      section = section_for(load_yaml(file), env || rails_env)
      return nil unless section.is_a?(Hash)

      section["url"] || build_url(section)
    rescue StandardError
      nil
    end

    def rails_env
      ENV["SCHEMA_REAPER_ENV"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
    end

    def load_yaml(file)
      rendered = ERB.new(File.read(file)).result
      begin
        YAML.safe_load(rendered, aliases: true)
      rescue ArgumentError # older Psych without the aliases: kwarg
        YAML.safe_load(rendered, [], [], true)
      end
    rescue StandardError
      # ERB that reaches into Rails -- Rails.application.credentials is the
      # common one -- cannot render outside a booted Rails process. Resolving
      # nothing yields a clear "no database_url configured"; parsing the file
      # un-rendered would build a connection URL out of template text.
      nil
    end

    # Rails 6+ allows `development: { primary: {...}, replica: {...} }`. Pick the
    # primary, or the first sub-config, when the env section is nested.
    def section_for(data, env)
      return nil unless data.is_a?(Hash)

      section = data[env] || data[env.to_s]
      return section unless nested?(section)

      section["primary"] || section.values.find { |v| v.is_a?(Hash) }
    end

    def nested?(section)
      section.is_a?(Hash) &&
        !section.key?("adapter") && !section.key?("url") && !section.key?("database") &&
        section.values.any?(Hash)
    end

    def build_url(section)
      adapter = section["adapter"].to_s
      return nil unless POSTGRES_ADAPTERS.include?(adapter)

      db = section["database"]
      return nil if db.to_s.empty?

      userinfo = [section["username"], section["password"]].compact.map { |v| escape(v) }.join(":")
      host = section["host"].to_s
      hostport = host.empty? ? "" : "#{host}#{":#{section["port"]}" if section["port"]}"
      auth = userinfo.empty? ? "" : "#{userinfo}@"

      "postgresql://#{auth}#{hostport}/#{db}"
    end

    # Passwords routinely contain characters that are structural in a URL.
    # An unescaped "@" makes libpq read the rest as the host, so it reports
    # a bogus hostname rather than a credential problem.
    def escape(value)
      ERB::Util.url_encode(value.to_s)
    end
  end
end
