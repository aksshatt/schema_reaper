# frozen_string_literal: true

module SchemaReaper
  module Reporters
    # Minimal ANSI styling. Colour is emitted only for an interactive terminal
    # and stays off when NO_COLOR is set, when output is redirected, or when
    # the caller forces it off.
    class Ansi
      CODES = {
        reset: 0, bold: 1, dim: 2,
        red: 31, green: 32, yellow: 33, blue: 34, magenta: 35, cyan: 36, grey: 90
      }.freeze

      SEVERITY_COLOUR = { high: :red, medium: :yellow, low: :cyan }.freeze

      def initialize(io: $stdout, enabled: nil)
        @on = enabled.nil? ? auto?(io) : enabled
      end

      def on?
        @on
      end

      # paint(:bold, :red) { "text" } or paint("text", :bold, :red)
      def paint(text, *styles)
        return text unless @on && !styles.empty?

        seq = styles.filter_map { |s| CODES[s] }.join(";")
        "\e[#{seq}m#{text}\e[0m"
      end

      def severity(sev, text = sev.to_s)
        paint(text, :bold, SEVERITY_COLOUR.fetch(sev, :grey))
      end

      # A five-cell bar for a 0.0..1.0 value, coloured by severity.
      def confidence_bar(value, sev)
        filled = (value * 5).round.clamp(0, 5)
        bar = ("█" * filled) + ("░" * (5 - filled))
        paint(bar, SEVERITY_COLOUR.fetch(sev, :grey))
      end

      private

      def auto?(io)
        return false if ENV["NO_COLOR"] && !ENV["NO_COLOR"].empty?
        return false unless io.respond_to?(:tty?) && io.tty?

        true
      end
    end
  end
end
