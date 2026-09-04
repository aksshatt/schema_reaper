# frozen_string_literal: true

require "prism"
require "set"

module SchemaReaper
  module Static
    # Walks the project and collects every identifier/symbol/string token that
    # could name a database column. Over-collects on purpose: a false "used" is
    # safe, a false "dead" is not.
    class Scanner
      RUBY_GLOB  = "**/*.rb"
      WORD_RE    = /[a-z_][a-z0-9_]*/i.freeze

      # Node classes whose #name (or #unescaped) is a bare identifier we treat
      # as a possible column/table reference.
      NAME_NODES = [
        Prism::CallNode, Prism::DefNode, Prism::ConstantReadNode,
        Prism::ConstantPathNode, Prism::ClassNode, Prism::ModuleNode,
        Prism::LocalVariableReadNode, Prism::CallTargetNode
      ].freeze

      def initialize(config, root: Dir.pwd)
        @config = config
        @root = root
      end

      # @return [Set<String>] lowercased tokens seen anywhere in the codebase
      def call
        tokens = Set.new
        ruby_files.each { |f| tokens.merge(ruby_tokens(f)) }
        view_files.each { |f| tokens.merge(text_tokens(f)) }
        tokens
      end

      private

      def ruby_files
        @config.scan_paths.flat_map do |p|
          Dir.glob(File.join(@root, p, RUBY_GLOB))
        end.uniq
      end

      def view_files
        @config.view_globs.flat_map { |g| Dir.glob(File.join(@root, g)) }.uniq
      end

      def ruby_tokens(path)
        src = File.read(path)
        out = Set.new
        result = Prism.parse(src)
        collect_from_node(result.value, out)
        # SQL string literals: pull bare words out of any string in the file.
        src.scan(/["'`]([^"'`]{0,4000})["'`]/) { |(s)| out.merge(s.scan(WORD_RE).map(&:downcase)) }
        out
      rescue StandardError
        text_tokens(path)
      end

      def collect_from_node(node, out)
        return unless node.is_a?(Prism::Node)

        out.merge(tokens_for(node))
        node.compact_child_nodes.each { |c| collect_from_node(c, out) }
      end

      def tokens_for(node)
        case node
        when Prism::SymbolNode
          [node.unescaped&.to_s&.downcase].compact
        when Prism::StringNode
          node.unescaped.to_s.scan(WORD_RE).map(&:downcase)
        when *NAME_NODES
          name = node.respond_to?(:name) ? node.name : nil
          [name&.to_s&.downcase].compact
        else
          []
        end
      end

      def text_tokens(path)
        File.read(path).scan(WORD_RE).to_set(&:downcase)
      rescue StandardError
        Set.new
      end
    end
  end
end
