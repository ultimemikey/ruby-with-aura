module Aura
  module Web
    module Middleware

      class RateLimiter
        DEFAULT_MAX_BUCKETS = 100_000

        def initialize(limit: 120, window: 60, max_buckets: DEFAULT_MAX_BUCKETS)
          @limit   = limit.to_i
          @window  = window.to_f
          @max_buckets = max_buckets.to_i
          raise ArgumentError, "limit must be positive" unless @limit.positive?
          raise ArgumentError, "window must be positive" unless @window.positive?
          raise ArgumentError, "max_buckets must be positive" unless @max_buckets.positive?

          @buckets = {}
          @mutex   = Mutex.new
        end

        def allow?(key)
          now = monotonic

          @mutex.synchronize do
            cleanup_expired(now)
            bucket = @buckets[key]

            if bucket.nil? || now - bucket[:start] >= @window
              if bucket.nil? && @buckets.size >= @max_buckets

                return [false, [@window.ceil, 1].max] if @buckets.size >= @max_buckets
              end
              @buckets.delete(key)
              @buckets[key] = { start: now, count: 1 }
              return [true, 0]
            end

            if bucket[:count] < @limit
              bucket[:count] += 1
              return [true, 0]
            end

            retry_after = (@window - (now - bucket[:start])).ceil
            [false, [retry_after, 1].max]
          end
        end

        def reset!
          @mutex.synchronize { @buckets.clear }
          nil
        end

        private

        def cleanup_expired(now)

          while (oldest = @buckets.first) && now - oldest[1][:start] >= @window
            @buckets.shift
          end
        end

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
