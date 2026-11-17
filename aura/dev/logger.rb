require "json"
require "time"

module Aura
  module Dev

    class Logger

      LEVELS = { debug: 0, info: 1, warn: 2, error: 3 }.freeze
      FORMATS = %i[pretty json].freeze

      CONTEXT_KEY = :aura_dev_logger_context

      class << self
        def shared
          @shared ||= new
        end

        attr_writer :shared
      end

      attr_reader :io, :format

      def initialize(io: $stdout, level: :info, format: :pretty)
        @io = io
        self.level  = level
        self.format = format
      end

      def level
        @level
      end

      def level=(value)
        @level = normalize_level(value)
      end

      def format=(value)
        @format = normalize_format(value)
      end

      def debug(message, **fields)
        log(:debug, message, **fields)
      end

      def info(message, **fields)
        log(:info, message, **fields)
      end

      def warn(message, **fields)
        log(:warn, message, **fields)
      end

      def error(message, **fields)
        log(:error, message, **fields)
      end

      def event(name, **fields)
        log(:info, name.to_s, event: name.to_s, **fields)
      end

      def with_fields(**fields, &block)
        raise ArgumentError, "with_fields requires a block" unless block

        stack = context_stack
        stack.push(fields)
        begin
          block.call
        ensure
          stack.pop
        end
      end

      private

      def log(severity, message, **fields)
        return false unless enabled?(severity)

        merged = context_stack.reduce({}) { |acc, layer| acc.merge(layer) }.merge(fields)
        @io.puts(render(severity, message, merged))
        true
      end

      def enabled?(severity)
        LEVELS.fetch(severity) >= LEVELS.fetch(@level)
      end

      def render(severity, message, fields)
        case @format
        when :json
          JSON.generate({ ts: timestamp, level: severity.to_s, msg: message.to_s }
                          .merge(fields.transform_keys(&:to_s)))
        else
          suffix = fields.empty? ? "" : " " + fields.map { |k, v| "#{k}=#{v}" }.join(" ")
          "#{timestamp} [#{severity.to_s.upcase}] #{message}#{suffix}"
        end
      end

      def timestamp
        Time.now.utc.iso8601
      end

      def context_stack
        Thread.current[CONTEXT_KEY] ||= []
      end

      def normalize_level(value)
        sym = value.to_s.downcase.to_sym
        raise ArgumentError, "unknown log level: #{value.inspect}" unless LEVELS.key?(sym)

        sym
      end

      def normalize_format(value)
        sym = value.to_s.downcase.to_sym
        raise ArgumentError, "unknown log format: #{value.inspect}" unless FORMATS.include?(sym)

        sym
      end
    end
  end
end
