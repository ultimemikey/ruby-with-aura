module Aura
  module Web
    module Server

      class LiveReloadWatcher
        WATCH_DIRS = %w[app public aura].freeze

        def self.start(dirs: WATCH_DIRS)
          new(dirs: dirs).tap(&:start)
        end

        def initialize(dirs: WATCH_DIRS)
          @dirs     = dirs.select { |d| File.directory?(d) }
          @changed  = false
          @mutex    = Mutex.new
          @listener = nil
        end

        def start
          return if @dirs.empty?

          require "listen"

          @listener = Listen.to(*@dirs, latency: 0.2) do |_modified, _added, _removed|
            @mutex.synchronize { @changed = true }
          end

          @listener.start
          self
        end

        def stop
          @listener&.stop
        end

        def changed?
          @mutex.synchronize do
            v = @changed
            @changed = false
            v
          end
        end

        def reset!
          @mutex.synchronize { @changed = false }
        end
      end
    end
  end
end
