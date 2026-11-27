# frozen_string_literal: true

require "json"
require "fileutils"
require "digest"

module SchemaReaper
  module Static
    # Per-file scan results keyed by mtime + size, so a re-scan only parses
    # the files that changed. Purely a speed-up: any problem reading or
    # writing it falls back to a full scan, never a wrong one.
    class Cache
      # Bumped whenever what a file contributes changes, so a cache written by
      # an older scanner is discarded instead of trusted.
      FORMAT = 3

      # path - where to keep it, or nil to disable
      # key  - anything else that changes a file's result (gem version, ...)
      def initialize(path, key:)
        @path = path
        # A digest, not #hash: Ruby seeds #hash per process, so a key built
        # with it never matches the one the previous run saved.
        @key = Digest::SHA256.hexdigest(JSON.generate([FORMAT, key]))
        @files = load
      end

      def lookup(file, kind)
        stamp = stamp_for(file, kind)
        hit = @files[file]
        return hit["entry"].merge("stamp" => stamp) if stamp && hit && hit["stamp"] == stamp

        yield.merge("stamp" => stamp)
      end

      def save(entries)
        return unless @path

        files = entries.to_h do |file, entry|
          [file, { "stamp" => entry["stamp"], "entry" => entry.reject { |k, _| k == "stamp" } }]
        end
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, JSON.generate("key" => @key, "files" => files))
      rescue StandardError
        nil
      end

      private

      def load
        return {} unless @path && File.exist?(@path)

        data = JSON.parse(File.read(@path))
        data["key"] == @key ? data["files"] : {}
      rescue StandardError
        {}
      end

      def stamp_for(file, kind)
        st = File.stat(file)
        "#{kind}:#{st.mtime.to_f}:#{st.size}"
      rescue SystemCallError
        nil
      end
    end
  end
end
