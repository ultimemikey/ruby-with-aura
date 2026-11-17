require_relative "memory_adapter"
require_relative "sqlite_adapter"
require_relative "record"

module Aura

  module DB

    class AdapterError < StandardError; end

    class << self
      attr_writer :adapter

      def connect(adapter: :memory, **options)
        self.adapter =
          case adapter
          when nil, :memory, :in_memory, "memory", "in_memory"
            MemoryAdapter.new(**options)
          when :sqlite, :sqlite3, "sqlite", "sqlite3"
            SQLiteAdapter.new(**options)
          else
            unless adapter.respond_to?(:query) && adapter.respond_to?(:execute)
              raise AdapterError, "unknown adapter: #{adapter.inspect}"
            end

            adapter
          end

        self.adapter
      end

      def adapter
        @adapter ||= MemoryAdapter.new
      end

      def connected?
        !@adapter.nil?
      end

      def disconnect
        @adapter = nil
        self
      end
    end
  end
end
