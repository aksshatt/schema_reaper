# frozen_string_literal: true

require "fileutils"

module SchemaReaper
  # Emits removal migrations: a two-step pair for a dead column (ignore, then
  # drop), or a single migration for an index (index:) or a whole table (no
  # column: and no index:).
  class MigrationGenerator
    # Enough of Rails' inflector for table names in this comment text -- a
    # wrong guess doesn't break anything functional, just reads oddly.
    SINGULAR_RULES = [
      [/ies\z/, "y"],               # activities -> activity
      [/(ss|sh|ch|x|z)es\z/, '\1'], # addresses  -> address, boxes -> box
      [/s\z/, ""]                   # employees  -> employee
    ].freeze

    def initialize(table:, column: nil, index: nil, dir: "db/migrate")
      raise ArgumentError, "pass column: or index:, not both" if column && index

      @table = table
      @column = column
      @index = index
      @dir = dir
    end

    def call
      FileUtils.mkdir_p(@dir)
      return [drop_index] if @index
      return [drop_table] unless @column

      [stage_one, stage_two]
    end

    private

    # CREATE/DROP INDEX CONCURRENTLY cannot run inside a transaction, hence
    # disable_ddl_transaction!. A partitioned index can't be dropped
    # concurrently at all, and the generator never sees the database, so the
    # migration checks pg_class itself when it runs. The down raises rather
    # than guessing at the index's definition; recreate it from db/schema.rb.
    def drop_index
      down_msg = "recreate #{@index} on :#{@table} from db/schema.rb if you need it back"
      write "remove_#{@index}", <<~RUBY
        # frozen_string_literal: true

        # Removes #{@index} -- concurrently, so writes to #{@table} are not
        # blocked, unless it is a partitioned index, which PostgreSQL can only
        # drop with a lock on the table and every partition.
        class Remove#{camelize(@index)} < ActiveRecord::Migration[#{migration_version}]
          disable_ddl_transaction!

          def up
            if partitioned_index?
              say "#{@index} is a partitioned index: dropping it without CONCURRENTLY (locks #{@table})"
              remove_index #{@table.to_sym.inspect}, name: #{@index.to_sym.inspect}, if_exists: true
            else
              remove_index #{@table.to_sym.inspect}, name: #{@index.to_sym.inspect}, algorithm: :concurrently, if_exists: true
            end
          end

          def down
            raise ActiveRecord::IrreversibleMigration, #{down_msg.inspect}
          end

          #{partitioned_check}
        end
      RUBY
    end

    # The generated migration's private helper, indented to sit inside the
    # class body (the first line lands where the template places it).
    def partitioned_check
      [
        "private",
        "",
        "def partitioned_index?",
        "  select_value(<<~SQL) == \"I\"",
        "    SELECT relkind FROM pg_class WHERE oid = to_regclass(\#{connection.quote(#{qualified_index.inspect})})",
        "  SQL",
        "end"
      ].map.with_index { |line, i| i.zero? || line.empty? ? line : "  #{line}" }.join("\n")
    end

    # An index lives in its table's schema; qualify it so to_regclass doesn't
    # depend on search_path.
    def qualified_index
      @table.include?(".") ? "#{@table.split(".").first}.#{@index}" : @index
    end

    def drop_table
      down_msg = "#{@table} and its rows are gone; restore from a backup if you need them back"
      write "drop_#{@table}", <<~RUBY
        # frozen_string_literal: true

        # Drops #{@table} and every row in it. Run only after confirming no
        # external consumer (reports, ETL, other services) reads it, and with
        # a backup taken. Remove the #{model} model, if any, in the same deploy.
        class Drop#{camelize(@table)}Table < ActiveRecord::Migration[#{migration_version}]
          def up
            drop_table #{@table.to_sym.inspect}
          end

          def down
            raise ActiveRecord::IrreversibleMigration, #{down_msg.inspect}
          end
        end
      RUBY
    end

    def stage_one
      note = "Add `self.ignored_columns += %w[#{@column}]` to the #{model} model, " \
             "then deploy STEP 2 after a soak period."
      write "ignore_#{@table}_#{@column}", <<~RUBY
        # frozen_string_literal: true

        # STEP 1 of 2. Deploy this alone and let it soak. It only tells
        # ActiveRecord to stop selecting the column; nothing is dropped.
        class Ignore#{camel}Column < ActiveRecord::Migration[#{migration_version}]
          def up
            say #{note.inspect}
          end

          def down
          end
        end
      RUBY
    end

    def stage_two
      down_msg = "recreate :#{@column} on :#{@table} manually if you need it back"
      write "drop_#{@table}_#{@column}", <<~RUBY
        # frozen_string_literal: true

        # STEP 2 of 2. Run only after STEP 1 has been deployed and verified in
        # production (nothing reads the column, no errors).
        class Drop#{camel}Column < ActiveRecord::Migration[#{migration_version}]
          def up
            remove_column :#{@table}, :#{@column}
          end

          def down
            raise ActiveRecord::IrreversibleMigration, #{down_msg.inspect}
          end
        end
      RUBY
    end

    def write(slug, body)
      @seq = (@seq || -1) + 1
      ts = (Time.now + @seq).strftime("%Y%m%d%H%M%S")
      path = File.join(@dir, "#{ts}_#{slug.tr(".", "_")}.rb")
      File.write(path, body)
      path
    end

    # Match the host app's Rails minor version when ActiveRecord is loaded,
    # otherwise a sane recent default the developer can edit.
    def migration_version
      return "7.1" unless defined?(ActiveRecord::VERSION::STRING)

      ActiveRecord::VERSION::STRING.split(".").first(2).join(".")
    end

    def camel
      camelize("#{@table}_#{@column}")
    end

    def camelize(str)
      str.split(/[_.]/).map(&:capitalize).join
    end

    def model
      singular.split("_").map(&:capitalize).join
    end

    def singular
      rule = SINGULAR_RULES.find { |pattern, _| @table.match?(pattern) }
      rule ? @table.sub(rule[0], rule[1]) : @table
    end
  end
end
