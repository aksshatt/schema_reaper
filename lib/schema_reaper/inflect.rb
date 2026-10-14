# frozen_string_literal: true

module SchemaReaper
  # Just enough of ActiveSupport's inflector to map model class names to
  # table names without depending on it. A wrong guess only weakens a
  # heuristic -- it never makes a finding more confident.
  module Inflect
    module_function

    def underscore(str)
      str.gsub(/([A-Z\d]+)([A-Z][a-z])/, '\\1_\\2').gsub(/([a-z\d])([A-Z])/, '\\1_\\2').downcase
    end

    def pluralize(word)
      case word
      when /[^aeiou]y\z/ then word.sub(/y\z/, "ies")
      when /(s|x|z|ch|sh)\z/ then "#{word}es"
      else "#{word}s"
      end
    end

    def singularize(word)
      case word
      when /ies\z/ then word.sub(/ies\z/, "y")
      when /(ss|sh|ch|x|z)es\z/ then word.sub(/es\z/, "")
      when /s\z/ then word.sub(/s\z/, "")
      else word
      end
    end

    # User -> users, LineItem -> line_items, Address -> addresses
    def tableize(class_name)
      pluralize(underscore(class_name))
    end
  end
end
