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

      # Macros that generate a real column from a differently-named virtual
      # attribute, so the literal column name never appears in application
      # code. Missing this made dead_column flag has_secure_password's
      # password_digest, and attr_encrypted/Lockbox/KMS ciphertext columns,
      # as unused even though they're the live backing store.
      DIGEST_MACROS = %w[has_secure_password].freeze
      DIGEST_SUFFIXES = %w[_digest].freeze
      ENCRYPTED_MACROS = %w[encrypts attr_encrypted lockbox_encrypts].freeze
      ENCRYPTED_SUFFIXES = %w[_ciphertext _iv _tag _encrypted].freeze

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
        when Prism::CallNode
          [node.name&.to_s&.downcase].compact + macro_derived_tokens(node)
        when *NAME_NODES
          name = node.respond_to?(:name) ? node.name : nil
          [name&.to_s&.downcase].compact
        else
          []
        end
      end

      # `has_secure_password` / `encrypts :field` / `attr_encrypted :field`
      # never write their generated column name (password_digest,
      # field_ciphertext, ...) anywhere in source -- only the virtual
      # attribute name. Derive the column names a macro call implies so they
      # count as "used" instead of looking dead.
      def macro_derived_tokens(node)
        call_name = node.name&.to_s
        return [] unless call_name

        if DIGEST_MACROS.include?(call_name)
          attrs = macro_symbol_args(node)
          attrs = ["password"] if attrs.empty?
          attrs.flat_map { |a| DIGEST_SUFFIXES.map { |s| "#{a}#{s}" } }
        elsif ENCRYPTED_MACROS.include?(call_name)
          macro_symbol_args(node).flat_map { |a| ENCRYPTED_SUFFIXES.map { |s| "#{a}#{s}" } }
        else
          []
        end
      end

      # Leading bare symbol arguments of a call, e.g. `encrypts :a, :b, purpose: :x`
      # => ["a", "b"]. Stops at the first non-symbol (keyword args, etc).
      def macro_symbol_args(node)
        args = node.arguments&.arguments || []
        args.take_while { |a| a.is_a?(Prism::SymbolNode) }
            .map { |a| a.unescaped.to_s.downcase }
      end

      def text_tokens(path)
        File.read(path).scan(WORD_RE).to_set(&:downcase)
      rescue StandardError
        Set.new
      end
    end
  end
end
