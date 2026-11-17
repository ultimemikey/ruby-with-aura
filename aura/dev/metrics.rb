module Aura
  module Dev

    class Metrics
      DEFAULT_TTL = 3600
      DEFAULT_MAX_ENTRIES = 1_000
      DEFAULT_MAX_SAMPLES = 1_000
      CLEANUP_INTERVAL = 64

      class << self
        def shared
          @shared ||= new
        end

        attr_writer :shared
      end

      def initialize(ttl: DEFAULT_TTL, max_entries: DEFAULT_MAX_ENTRIES, max_samples: DEFAULT_MAX_SAMPLES)
        @ttl = ttl.to_f
        @max_entries = max_entries.to_i
        @max_samples = max_samples.to_i
        raise ArgumentError, "ttl must be positive" unless @ttl.positive?
        raise ArgumentError, "max_entries must be positive" unless @max_entries.positive?
        raise ArgumentError, "max_samples must be positive" unless @max_samples.positive?

        @mutex = Mutex.new
        @counters = {}
        @timings = {}
        @gauges = []
        @operations = 0
      end

      def increment(name, by = 1)
        @mutex.synchronize do
          current_time = clock
          prune_periodically(current_time)
          metric_key = key(name)
          entry = @counters[metric_key]
          unless entry
            prune_expired(current_time) if @counters.size >= @max_entries
            evict_oldest(@counters) if @counters.size >= @max_entries
            entry = @counters[metric_key] = { value: 0, updated_at: current_time }
          end
          entry[:value] += by
          entry[:updated_at] = current_time
          entry[:value]
        end
      end

      def timing(name, seconds)
        value = seconds.to_f
        @mutex.synchronize do
          current_time = clock
          prune_periodically(current_time)
          record_timing(key(name), value, current_time)
        end
        value
      end

      def observe(name, value)
        @mutex.synchronize do
          current_time = clock
          prune_periodically(current_time)
          @gauges.shift while @gauges.size >= @max_samples
          @gauges << { name: key(name), value: value, recorded_at: current_time }
        end
        value
      end

      def measure(name)
        started = clock
        yield
      ensure
        timing(name, clock - started)
      end

      def counter(name)
        @mutex.synchronize do
          current_time = clock
          prune_expired(current_time)
          @counters.dig(key(name), :value) || 0
        end
      end

      def timer(name)
        @mutex.synchronize do
          current_time = clock
          prune_expired(current_time)
          stats(key(name))
        end
      end

      def snapshot
        @mutex.synchronize do
          current_time = clock
          prune_expired(current_time)
          {
            counters: @counters.each_with_object({}) do |(name, entry), acc|
              acc[name] = entry[:value]
            end,
            timings: @timings.each_with_object({}) do |(name, _), acc|
              acc[name] = stats(name)
            end,
            gauges:   @gauges.map { |sample| { name: sample[:name], value: sample[:value] } }
          }
        end
      end

      def reset!
        @mutex.synchronize do
          @counters = {}
          @timings  = {}
          @gauges   = []
          @operations = 0
        end
        self
      end

      private

      def key(name)
        name.to_s
      end

      def clock
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def record_timing(metric_key, seconds, current_time)
        samples = @timings[metric_key]
        unless samples
          prune_expired(current_time) if @timings.size >= @max_entries
          evict_oldest(@timings) if @timings.size >= @max_entries
          samples = @timings[metric_key] = []
        end
        samples << [current_time, seconds]
        samples.shift while samples.size > @max_samples
      end

      def stats(metric_key)
        values = Array(@timings[metric_key]).map(&:last)
        total = values.sum
        {
          count: values.length,
          total: total,
          min: values.min,
          max: values.max,
          avg: values.empty? ? 0.0 : total / values.length
        }
      end

      def prune_periodically(current_time)
        @operations += 1
        prune_expired(current_time) if (@operations % CLEANUP_INTERVAL).zero?
      end

      def prune_expired(current_time)
        cutoff = current_time - @ttl
        @counters.delete_if { |_name, entry| entry[:updated_at] <= cutoff }
        @timings.each_value { |samples| samples.shift while samples.first && samples.first[0] <= cutoff }
        @timings.delete_if { |_name, samples| samples.empty? }
        @gauges.shift while @gauges.first && @gauges.first[:recorded_at] <= cutoff
      end

      def evict_oldest(collection)
        key, = collection.min_by do |_name, entry|
          entry.is_a?(Array) ? (entry.last&.first || 0) : entry[:updated_at]
        end
        collection.delete(key)
      end
    end
  end
end
