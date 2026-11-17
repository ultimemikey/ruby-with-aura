module Aura
  module Dev

    class Reloader
      attr_reader :root, :patterns

      def initialize(root, patterns: %w[**/*.rb])
        @root      = File.expand_path(root)
        @patterns  = patterns
        @mutex     = Mutex.new
        @callbacks = []
        @snapshot  = current_snapshot
        @changed   = []
      end

      def scan!
        current = current_snapshot

        @mutex.synchronize do
          @changed = current.each_with_object([]) do |(path, mtime), acc|
            acc << path if @snapshot[path] != mtime
          end.sort
          @snapshot = current
        end

        @changed
      end

      def changed
        @mutex.synchronize { @changed.dup }
      end

      def dirty?
        !changed.empty?
      end

      def on_change(&block)
        raise ArgumentError, "on_change requires a block" unless block

        @mutex.synchronize { @callbacks << block }
        self
      end

      def check!
        scan!
        return false unless dirty?

        changed_files = changed
        callbacks = @mutex.synchronize { @callbacks.dup }
        callbacks.each { |cb| cb.call(changed_files) }
        true
      end

      private

      def current_snapshot
        matched_files.each_with_object({}) { |path, acc| acc[path] = File.mtime(path) }
      end

      def matched_files
        @patterns
          .flat_map { |pattern| Dir.glob(File.join(@root, pattern)) }
          .select { |path| File.file?(path) }
          .uniq
          .sort
      end
    end
  end
end
