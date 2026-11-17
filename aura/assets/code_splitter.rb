require "json"
require "fileutils"
require_relative "fingerprint"

module Aura
  module Assets

    module CodeSplitter
      module_function

      def split(route_assets, out_dir: "dist")
        ::FileUtils.mkdir_p(out_dir)

        shared = shared_files(route_assets)

        chunks = {}
        route_assets.each do |route, files|
          files = Array(files)
          own   = files - shared
          own   = files if own.empty?

          source = own.map { |file| read_source(file) }.join("\n")
          name   = "chunk-#{Fingerprint.digest(source)}.js"

          ::File.write(::File.join(out_dir, name), source, mode: "w", encoding: "utf-8")
          chunks[route] = name
        end

        ::File.write(
          ::File.join(out_dir, "chunk-manifest.json"),
          JSON.pretty_generate({ chunks: chunks, shared: shared }),
          mode: "w", encoding: "utf-8"
        )

        { chunks: chunks, shared: shared }
      end

      def shared_files(route_assets)
        counts = Hash.new(0)
        route_assets.each_value { |files| Array(files).each { |file| counts[file] += 1 } }
        counts.select { |_, count| count > 1 }.keys.sort
      end

      def read_source(file)
        ::File.exist?(file) ? ::File.read(file, encoding: "utf-8") : ""
      end
    end
  end
end
