module Aura
  module Deploy

    class GracefulShutdown
      DEFAULT_TIMEOUT = 30
      DEFAULT_SIGNALS = %w[TERM INT].freeze

      attr_reader :timeout, :signals

      def initialize(timeout: DEFAULT_TIMEOUT, signals: DEFAULT_SIGNALS)
        @timeout  = timeout
        @signals  = Array(signals)
        @stopping = false
        @on_stop  = nil
      end

      def install(&on_stop)
        @on_stop = on_stop if block_given?

        installed = []
        @signals.each do |sig|
          begin
            Signal.trap(sig) { stop! }
            installed << sig
          rescue ArgumentError, TypeError

          end
        end
        installed
      end

      def stopping?
        @stopping
      end

      def stop!
        return false if @stopping

        @stopping = true
        @on_stop&.call
        true
      end

      def wait(timeout = @timeout)
        deadline = monotonic + timeout.to_f

        loop do
          return true if @stopping

          remaining = deadline - monotonic
          return false if remaining <= 0

          sleep(remaining > 0.05 ? 0.05 : remaining)
        end
      end

      private

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
