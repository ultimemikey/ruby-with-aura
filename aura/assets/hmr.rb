module Aura
  module Assets

    class HMR
      EXTENSIONS = %w[.js .css .rb].freeze

      attr_reader :root

      def initialize(root)
        @root     = ::File.expand_path(root.to_s)
        @snapshot = {}
      end

      def scan!
        @snapshot = snapshot
      end

      def changed
        current = snapshot

        current.each_with_object([]) do |(path, signature), acc|
          previous = @snapshot[path]
          acc << path if previous.nil? || previous != signature
        end.sort
      end

      def payload
        { type: "hmr", changed: changed }
      end

      def watch(interval: 1)
        loop do
          sleep interval

          next if changed.empty?

          yield payload
          @snapshot = snapshot
        end
      end

      def snapshot
        ::Dir.glob(::File.join(@root, "**", "*")).sort.each_with_object({}) do |path, acc|
          next unless ::File.file?(path)
          next unless EXTENSIONS.include?(::File.extname(path).downcase)

          stat = ::File.stat(path)
          acc[path] = [stat.mtime.to_f, stat.size]
        end
      end
    end
  end
end
