# frozen_string_literal: true

# Prints the real `schema_reaper scan` table report that docs/assets/terminal.svg
# replays. No database needed: a fixture schema is fed to the real Runner and
# Table reporter, and the codebase it scans is a two-model app written to a
# temp dir. When the reporter's output changes, run this and copy the lines
# into LINES in make_svgs.py.
#
#   bundle exec ruby -Ilib docs/svg/sample_output.rb

require "schema_reaper"
require "tmpdir"

MODELS = {
  "user.rb" => <<~RUBY,
    class User < ApplicationRecord
      belongs_to :team
      validates :email, presence: true
      def masked_api_key
        api_key&.last(4)
      end
    end
  RUBY
  "team.rb" => <<~RUBY
    class Team < ApplicationRecord
      has_many :users
      validates :name, presence: true
    end
  RUBY
}.freeze

def column(name, type: "integer", null: true, bytes: 4, null_fraction: nil)
  SchemaReaper::Column.new(name: name, sql_type: type, null: null, default: nil, bytes: bytes,
                           null_fraction: null_fraction, distinct_values: nil)
end

def table(name, columns, row_count:, foreign_keys: [])
  SchemaReaper::Table.new(name: name, columns: columns, indexes: [], primary_key: "id",
                          foreign_keys: foreign_keys, row_count: row_count)
end

SCHEMA = SchemaReaper::DatabaseSchema.new(
  index_scan_total: 10_000,
  tables: [
    table("users", [
            column("id"), column("email", type: "varchar", null: false, null_fraction: 0.0),
            column("team_id", null_fraction: 0.0),
            column("api_key", type: "varchar", bytes: 16, null_fraction: 1.0),
            column("created_at", type: "timestamp", bytes: 8), column("updated_at", type: "timestamp", bytes: 8)
          ], row_count: 3000, foreign_keys: %w[team_id]),
    table("teams", [column("id"), column("name", type: "varchar", bytes: 12)], row_count: 40),
    table("stale_exports", [column("id"), column("payload", type: "text", bytes: 200)], row_count: 0)
  ]
)

Dir.mktmpdir do |root|
  FileUtils.mkdir_p(File.join(root, "app/models"))
  MODELS.each { |file, source| File.write(File.join(root, "app/models", file), source) }

  config = SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.merge("gem_awareness" => false), root: root)
  runtime = SchemaReaper::Runtime::Report.empty
  findings = SchemaReaper::Runner.new(config: config, root: root, introspector: -> { SCHEMA }, runtime: runtime).run
  SchemaReaper::Reporters::Table.new(findings, color: false).render
end
