# frozen_string_literal: true

require "prism"
require "set"

module SchemaReaper
  module Static
    # Everything a scan learned.
    #   tokens       - Set<String>, every token in every scanned file
    #   shared       - Set<String>, tokens from files that are not models
    #   models       - Array<ModelFile>, one per ActiveRecord model file
    #   keeps        - Hash{String => String}, `# schema_reaper:keep` targets
    #                  => the reason given ("" when none)
    Result = Struct.new(:tokens, :shared, :models, :keeps, keyword_init: true) do
      def self.from_tokens(tokens)
        new(tokens: tokens.to_set, shared: tokens.to_set, models: [], keeps: {})
      end
    end

    # tables: every table this model file may be about -- one normally, two
    # for a namespaced class (Admin::Report -> reports, or admin_reports with
    # a table_name_prefix), the root model's for an STI subclass.
    ModelFile = Struct.new(:path, :tables, :tokens, keyword_init: true)

    # Walks the project and collects every identifier/symbol/string token that
    # could name a database column. Over-collects on purpose: a false "used" is
    # safe, a false "dead" is not.
    class Scanner
      # `# schema_reaper:keep legacy_token, users.api_key -- read by the billing ETL`
      KEEP_RE = /#\s*schema_reaper:keep\s+(.+?)\s*(?:--\s*(.*?))?\s*$/.freeze

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
        scan.tokens
      end

      # @return [Result]
      def scan
        cache = Cache.new(@config.scan_cache && File.expand_path(@config.scan_cache, @root),
                          key: [SchemaReaper::VERSION, MACRO_COLUMN_TEMPLATES.keys])
        entries = ruby_files.map { |f| [f, cache.lookup(f, :ruby) { ruby_entry(f) }] } +
                  view_files.map { |f| [f, cache.lookup(f, :view) { view_entry(f) }] }
        cache.save(entries)
        build_result(entries)
      end

      private

      def build_result(entries)
        tokens = Set.new
        shared = Set.new
        models = []
        keeps = {}
        tables = ModelResolver.new(entries.filter_map { |_, e| e["model"] }).tables
        entries.each do |path, entry|
          file_tokens = entry["tokens"].to_set
          tokens.merge(file_tokens)
          keeps.merge!(entry["keeps"])
          model_tables = entry["model"] && tables[entry["model"]["path"]]
          if model_tables
            models << ModelFile.new(path: path, tables: model_tables, tokens: file_tokens)
          else
            shared.merge(file_tokens) # not a model we could place: its names count everywhere
          end
        end
        Result.new(tokens: tokens, shared: shared, models: models, keeps: keeps)
      end

      def ruby_entry(path)
        src = File.read(path)
        {
          "tokens" => ruby_tokens(path, src).to_a,
          "model" => model_file?(path) ? ModelResolver.facts(src) : nil,
          "keeps" => keeps_in(src)
        }
      rescue StandardError
        view_entry(path)
      end

      def view_entry(path)
        src = File.read(path)
        { "tokens" => text_tokens(path).to_a, "model" => nil, "keeps" => keeps_in(src) }
      rescue StandardError
        { "tokens" => [], "model" => nil, "keeps" => {} }
      end

      def keeps_in(src)
        src.scan(KEEP_RE).each_with_object({}) do |(targets, reason), out|
          targets.split(/[\s,]+/).reject(&:empty?).each { |t| out[t.downcase] = reason.to_s }
        end
      end

      def model_file?(path)
        path.include?("/app/models/")
      end

      def ruby_files
        @config.scan_paths.flat_map do |p|
          Dir.glob(File.join(@root, p, RUBY_GLOB))
        end.uniq
      end

      def view_files
        @config.view_globs.flat_map { |g| Dir.glob(File.join(@root, g)) }.uniq
      end

      def ruby_tokens(path, src = File.read(path))
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

    # Maps model classes to the tables they read, from the facts the scanner
    # collected. A class counts as a model only if it inherits from
    # ApplicationRecord / ActiveRecord::Base / another abstract base, or from
    # another model (STI); anything else in app/models -- a PORO, a Struct,
    # a form object -- is not placed, so its names stay shared. Getting this
    # wrong in the narrow direction would hide real use, so every doubt
    # resolves to "shared".
    class ModelResolver
      AR_ROOTS = %w[ApplicationRecord ActiveRecord::Base].freeze

      # What an app/models file says about the class it defines; ModelResolver
      # turns these into tables once every file has been read (an STI
      # subclass needs its parent's facts). A file with no `class X < Y` --
      # a concern, a module -- has none and stays shared code.
      def self.facts(src)
        match = src.match(/^\s*class\s+((?:\w+::)*\w+)\s*<\s*((?:::)?[\w:]+)/)
        return nil unless match

        # `module Admin` wrapping the class namespaces it as much as `Admin::`
        modules = src[0...match.begin(0)].scan(/^\s*module\s+([\w:]+)/).flatten.flat_map { |m| m.split("::") }
        parts = modules + match[1].split("::")
        {
          "path" => parts.join("::"),          # Admin::User -- the identity
          "class" => parts.last,
          "namespace" => parts[0..-2].join("_"),
          "superclass" => match[2],            # as written; resolved like Ruby would
          "table" => src[/self\.table_name\s*=\s*["':]([\w.]+)/, 1],
          "abstract" => src.match?(/self\.abstract_class\s*=\s*true/)
        }
      end

      # Keyed by the full class path: User and Admin::User are different
      # models, and keying by the bare name let one overwrite the other.
      # A class reopened in a second file merges its facts.
      def initialize(facts)
        @by_path = facts.each_with_object({}) do |f, h|
          h[f["path"]] = h.key?(f["path"]) ? h[f["path"]].merge(f) { |_, old, new| old || new } : f
        end
      end

      # @return [Hash{String => Array<String>}] class path => tables; abstract
      #   and unplaceable classes are absent
      def tables
        @by_path.each_key.with_object({}) do |path, out|
          resolved = tables_for(path, Set.new)
          out[path] = resolved if resolved&.any?
        end
      end

      private

      def tables_for(path, seen)
        facts = @by_path[path]
        return nil if facts.nil? || facts["abstract"] || seen.include?(path)

        seen << path
        return [facts["table"]] if facts["table"]
        return own_tables(facts) if root?(facts)

        parent = resolve(facts["superclass"], facts["path"])
        tables_for(parent, seen) if parent # STI: the parent's table
      end

      def root?(facts)
        sup = facts["superclass"].sub(/\A::/, "")
        return true if AR_ROOTS.include?(sup) || AR_ROOTS.include?(sup.split("::").last)

        base = @by_path[resolve(facts["superclass"], facts["path"])]
        base && base["abstract"] && !base["table"]
      end

      # Ruby's constant lookup, approximately: `class Admin::Report < User`
      # means Admin::User if that exists, else ::User. A leading :: skips
      # straight to the top level. nil when no scanned model matches.
      def resolve(name, from_path)
        return @by_path.key?(name[2..]) ? name[2..] : nil if name.start_with?("::")

        scope = from_path.split("::")[0..-2]
        until scope.empty?
          candidate = (scope + [name]).join("::")
          return candidate if @by_path.key?(candidate)

          scope = scope[0..-2]
        end
        @by_path.key?(name) ? name : nil
      end

      def own_tables(facts)
        table = Inflect.tableize(facts["class"])
        ns = facts["namespace"]
        ns.empty? ? [table] : [table, "#{Inflect.underscore(ns)}_#{table}"]
      end
    end
  end
end
