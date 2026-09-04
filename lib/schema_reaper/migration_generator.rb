# frozen_string_literal: true

require "fileutils"

module SchemaReaper
  # Emits a two-step, reversible migration pair for a dead column.
  class MigrationGenerator
    def initialize(table:, column:, dir: "db/migrate")
      @table = table
      @column = column
      @dir = dir
    end

    def call
      FileUtils.mkdir_p(@dir)
      [stage_one, stage_two]
    end

    private

    def stage_one
      write "ignore_#{@table}_#{@column}", <<~RUBY
        # frozen_string_literal: true

        # STEP 1 of 2. Deploy this alone and let it soak. It only tells
        # ActiveRecord to stop selecting the column; nothing is dropped.
        class Ignore#{camel}Column < ActiveRecord::Migration[7.1]
          def up
            say "Add `self.ignored_columns += %w[#{@column}]` to the #{model} model, " \
                "then deploy STEP 2 after a soak period."
          end

          def down; end
        end
      RUBY
    end

    def stage_two
      write "drop_#{@table}_#{@column}", <<~RUBY
        # frozen_string_literal: true

        # STEP 2 of 2. Run only after STEP 1 has been deployed and verified.
        class Drop#{camel}Column < ActiveRecord::Migration[7.1]
          def up
            remove_column :#{@table}, :#{@column}
          end

          def down
            raise ActiveRecord::IrreversibleMigration,
                  "recreate :#{@column} on :#{@table} manually if you need it back"
          end
        end
      RUBY
    end

    def write(slug, body)
      @seq = (@seq || -1) + 1
      ts = (Time.now + @seq).strftime("%Y%m%d%H%M%S")
      path = File.join(@dir, "#{ts}_#{slug}.rb")
      File.write(path, body)
      path
    end

    def camel
      "#{@table}_#{@column}".split("_").map(&:capitalize).join
    end

    def model
      @table.split("_").map(&:capitalize).join.sub(/s$/, "")
    end
  end
end
