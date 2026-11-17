require "json"

module Aura
  module Dev

    class Tracer

      STACK_KEY = :aura_dev_tracer_stack
      DEFAULT_TTL = 3600
      DEFAULT_MAX_SPANS = 10_000
      CLEANUP_INTERVAL = 64

      class << self
        def shared
          @shared ||= new
        end

        attr_writer :shared
      end

      def initialize(ttl: DEFAULT_TTL, max_spans: DEFAULT_MAX_SPANS)
        @ttl = ttl.to_f
        @max_spans = max_spans.to_i
        raise ArgumentError, "ttl must be positive" unless @ttl.positive?
        raise ArgumentError, "max_spans must be positive" unless @max_spans.positive?

        @mutex = Mutex.new
        @spans = []
        @next_id = 0
        @operations = 0
      end

      def trace(name, **attrs)
        stack     = span_stack
        parent_id = stack.last
        id        = allocate_id
        started   = clock

        stack.push(id)
        begin
          yield
        ensure
          stack.pop
          duration = (clock - started) * 1000.0
          @mutex.synchronize do
            current_time = clock
            prune_periodically(current_time)
            prune_expired(current_time) if @spans.size >= @max_spans
            @spans.shift while @spans.size >= @max_spans
            @spans << {
              id: id,
              name: name.to_s,
              parent_id: parent_id,
              duration_ms: duration,
              attrs: attrs,
              recorded_at: current_time
            }
          end
        end
      end

      def spans
        @mutex.synchronize do
          prune_expired(clock)
          @spans.map { |span| span.reject { |key, _| key == :recorded_at } }
        end
      end

      def to_json(*_args)
        JSON.generate(spans)
      end

      def reset!
        @mutex.synchronize do
          @spans   = []
          @next_id = 0
        end
        self
      end

      private

      def span_stack
        Thread.current[STACK_KEY] ||= []
      end

      def allocate_id
        @mutex.synchronize { @next_id += 1 }
      end

      def clock
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def prune_periodically(current_time)
        @operations += 1
        prune_expired(current_time) if (@operations % CLEANUP_INTERVAL).zero?
      end

      def prune_expired(current_time)
        cutoff = current_time - @ttl
        @spans.shift while @spans.first && @spans.first[:recorded_at] <= cutoff
      end
    end
  end
end
