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

      # Macros whose generated column name differs from the virtual attribute
      # declared in the call, so the real column name never appears anywhere
      # in application code and would otherwise look dead. %s is replaced with
      # the declared attribute.
      #
      # Several shapes are listed for some macros on purpose: getting the real
      # default right matters most, but an extra guess that never matches a
      # real column is harmless -- over-collecting is this scanner's stated
      # design, and both attr_encrypted and Lockbox let a call override their
      # naming, which a static scan cannot always evaluate.
      #
      # attr_encrypted's own default is a PREFIX (encrypted_<attr>), not a
      # suffix -- confirmed against the gem's own attr_encrypted_default_options
      # (prefix: "encrypted_", suffix: ""). The suffix form is kept as a
      # fallback for calls that override it.
      #
      # Lockbox's real macro is has_encrypted, not lockbox_encrypts.
      #
      # Rails' own `encrypts` has no entry: it stores ciphertext in the
      # original column, so the bare attribute name is what needs to be
      # "used", and that is already picked up as a symbol literal by
      # tokens_for below -- do not add a suffix pattern for it.
      MACRO_COLUMN_TEMPLATES = {
        "has_secure_password" => ["%s_digest"],
        "attr_encrypted" => ["encrypted_%s", "%s_encrypted", "%s_ciphertext"],
        "has_encrypted" => ["%s_ciphertext", "%s_iv", "%s_tag"]
      }.freeze

      # The attribute a macro implies when called with no explicit name, e.g.
      # bare `has_secure_password` -> :password.
      MACRO_DEFAULT_ATTR = { "has_secure_password" => "password" }.freeze

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
        out.merge(macro_derived_tokens(node)) if node.is_a?(Prism::CallNode)
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

      def macro_derived_tokens(node)
        call_name = node.name&.to_s
        templates = call_name && MACRO_COLUMN_TEMPLATES[call_name]
        return [] unless templates

        attrs = macro_symbol_args(node)
        attrs = [MACRO_DEFAULT_ATTR[call_name]].compact if attrs.empty?
        attrs.product(templates).map { |attr, template| format(template, attr) }
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
