module Aura
  module Core
    module Cache

      class Store
        DEFAULT_TTL = 60
        DEFAULT_MAX_TTL = 3600
        DEFAULT_MAX_ENTRIES = 10_000
        CLEANUP_INTERVAL = 64

        def self.shared
          @shared ||= new
        end

        def initialize(max_entries: DEFAULT_MAX_ENTRIES, max_ttl: DEFAULT_MAX_TTL)
          @max_entries = max_entries.to_i
          @max_ttl = max_ttl.to_f
          raise ArgumentError, "max_entries must be positive" unless @max_entries.positive?
          raise ArgumentError, "max_ttl must be positive" unless @max_ttl.positive?

          @entries = {}
          @mutex   = Mutex.new
          @operations = 0
        end

        def fetch(key, ttl: DEFAULT_TTL)
          current_time = now
          entry = @mutex.synchronize do
            prune_periodically(current_time)
            found = @entries[key]
            if found && found[:expires_at] > current_time
              @entries.delete(key)
              @entries[key] = found
            else
              @entries.delete(key)
              nil
            end
          end
          return entry[:value] if entry

          value = yield

          @mutex.synchronize do
            current_time = now
            prune_expired(current_time)
            @entries.shift while @entries.size >= @max_entries
            @entries[key] = {
              value: value,
              expires_at: current_time + effective_ttl(ttl)
            }
          end
          value
        end

        def revalidate(*keys)
          return clear if keys.empty?

          @mutex.synchronize { keys.each { |k| @entries.delete(k) } }
          nil
        end

        def clear
          @mutex.synchronize { @entries.clear }
          nil
        end

        def key?(key)
          current_time = now
          @mutex.synchronize do
            entry = @entries[key]
            if entry && entry[:expires_at] > current_time
              true
            else
              @entries.delete(key)
              false
            end
          end
        end

        private

        def effective_ttl(ttl)
          ttl.nil? ? @max_ttl : [[ttl.to_f, 0.0].max, @max_ttl].min
        end

        def prune_periodically(current_time)
          @operations += 1
          prune_expired(current_time) if (@operations % CLEANUP_INTERVAL).zero?
        end

        def prune_expired(current_time)
          @entries.delete_if { |_key, entry| entry[:expires_at] <= current_time }
        end

        def now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
