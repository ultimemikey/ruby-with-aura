require "securerandom"
require "json"

module Aura
  module Web
    module Server

      module SessionStore

        def self.build(store_type = nil)
          store_type ||= ENV.fetch("AURA_SESSION_STORE", "memory")

          case store_type.to_s.downcase
          when "redis"
            RedisStore.new(
              url: ENV.fetch("REDIS_URL", "redis://localhost:6379"),
              ttl: ENV.fetch("AURA_SESSION_TTL", "3600").to_i
            )
          when "memory"
            MemoryStore.new(
              max_size: ENV.fetch("AURA_SESSION_MEMORY_MAX", "5000").to_i,
              ttl: ENV.fetch("AURA_SESSION_TTL", "3600").to_i
            )
          else
            ::Kernel.raise ::ArgumentError,
              "[Aura] Unknown AURA_SESSION_STORE=#{store_type.inspect}. Supported: memory, redis."
          end
        end

        class Base

          def read(session_id)
            raise NotImplementedError
          end

          def write(session_id, data)
            raise NotImplementedError
          end

          def delete(session_id)
            raise NotImplementedError
          end

          def generate_id
            SecureRandom.urlsafe_base64(32)
          end

          def rotate(old_id)
            data = read(old_id)
            new_id = generate_id
            delete(old_id)
            write(new_id, data)
            new_id
          end
        end

        class MemoryStore < Base
          Entry = Struct.new(:data, :expires_at)

          def initialize(max_size: 5000, ttl: 3600)
            @max_size = max_size
            @ttl      = ttl
            @store    = {}
            @mutex    = Mutex.new
          end

          def read(session_id)
            @mutex.synchronize do
              entry = @store[session_id]
              if entry.nil? || expired?(entry)
                @store.delete(session_id)
                new_entry = fresh_entry
                @store[session_id] = new_entry
                evict_if_needed
                new_entry.data
              else

                entry.expires_at = Time.now + @ttl
                entry.data
              end
            end
          end

          def write(session_id, data)
            @mutex.synchronize do
              @store[session_id] = Entry.new(data, Time.now + @ttl)
              evict_if_needed
            end
          end

          def delete(session_id)
            @mutex.synchronize { @store.delete(session_id) }
          end

          def size
            @mutex.synchronize { @store.size }
          end

          private

          def fresh_entry
            Entry.new({}, Time.now + @ttl)
          end

          def expired?(entry)
            Time.now > entry.expires_at
          end

          def evict_if_needed
            return unless @store.size > @max_size

            @store.reject! { |_, entry| expired?(entry) }

            if @store.size > @max_size
              to_drop = @store.size - (@max_size / 2)
              @store.keys.first(to_drop).each { |k| @store.delete(k) }
            end
          end
        end

        class RedisStore < Base
          def initialize(url: "redis://localhost:6379", ttl: 3600)
            require "redis"
            @redis = Redis.new(url: url)
            @ttl   = ttl
          end

          def read(session_id)
            raw = @redis.get(session_key(session_id))
            if raw
              @redis.expire(session_key(session_id), @ttl)
              JSON.parse(raw, symbolize_names: true)
            else
              @redis.setex(session_key(session_id), @ttl, JSON.generate({}))
              {}
            end
          rescue StandardError
            {}
          end

          def write(session_id, data)
            @redis.setex(session_key(session_id), @ttl, JSON.generate(data))
          rescue StandardError
            nil
          end

          def delete(session_id)
            @redis.del(session_key(session_id))
          rescue StandardError
            nil
          end

          private

          def session_key(id)
            "aura:session:#{id}"
          end
        end
      end
    end
  end
end
