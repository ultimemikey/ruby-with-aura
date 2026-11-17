require "json"
require "fileutils"

module Aura
  module Assets

    class Manifest
      FILENAME = "asset-manifest.json"

      attr_reader :dir

      def initialize(dir = "dist")
        @dir  = dir
        @data = {}
      end

      def self.load(path)
        path = path.to_s
        manifest = new(::File.dirname(path))
        manifest.data.merge!(read(path))
        manifest
      end

      def self.read(path)
        return {} unless ::File.file?(path)

        parsed = JSON.parse(::File.read(path, encoding: "utf-8"))
        parsed.is_a?(::Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def path
        ::File.join(@dir, FILENAME)
      end

      def set(logical, hashed)
        @data[logical.to_s] = hashed.to_s
      end

      def get(logical)
        @data[logical.to_s]
      end

      def digest
        @data
      end
      alias data digest

      def write!
        ::FileUtils.mkdir_p(@dir)
        ::File.write(path, JSON.pretty_generate(@data), mode: "w", encoding: "utf-8")
        path
      end
    end
  end
end
