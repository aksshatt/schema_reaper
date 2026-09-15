# frozen_string_literal: true

require_relative "ansi"

module SchemaReaper
  module Reporters
    # Shared styling for the CLI's short command output (baseline, trend,
    # generate-migration, the CI gate and stderr notices). Keeps every command
    # looking like it belongs to the same tool.
    class Console
      def initialize(out: $stdout, err: $stderr, color: nil)
        @out = out
        @err = err
        @a = Ansi.new(io: out, enabled: color)
        @ae = Ansi.new(io: err, enabled: color)
      end

      def blank
        @out.puts
      end

      # "  schema_reaper trend  ·  3 snapshots"
      def title(command, meta = nil)
        # +"" : on Ruby <= 2.7 an interpolated string whose parts are all frozen
        # literals is itself frozen, so the append below raises FrozenError.
        line = +"  #{@a.paint("schema_reaper", :bold)} #{@a.paint(command, :bold)}"
        line << "  #{@a.paint("·  #{meta}", :dim)}" if meta
        @out.puts
        @out.puts line
        @out.puts
      end

      def ok(message)
        @out.puts "  #{@a.paint("✓", :green, :bold)} #{message}"
      end

      def info(message)
        @out.puts "  #{message}"
      end

      # aligned "label   value  (aside)" row
      def row(label, value, aside = nil)
        text = format("  %-15s %s", label, @a.paint(value.to_s, :bold))
        text << "  #{@a.paint("(#{aside})", :dim)}" if aside && !aside.empty?
        @out.puts text
      end

      def list(heading, items, colour: :dim)
        return if items.empty?

        @out.puts "  #{@a.paint(heading, colour)}" if heading && !heading.empty?
        items.each { |i| @out.puts "    #{@a.paint("- #{i}", colour)}" }
      end

      # A single stderr notice, e.g. the unused-index skip.
      def notice(message)
        @err.puts "  #{@ae.paint("!", :yellow, :bold)} #{message}"
      end

      def problem(message, items: [])
        @err.puts
        @err.puts "  #{@ae.paint("✗", :red, :bold)} #{@ae.paint(message, :bold)}"
        items.each { |i| @err.puts "    #{@ae.paint("- #{i}", :red)}" }
      end
    end
  end
end
