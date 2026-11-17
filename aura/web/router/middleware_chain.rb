module Aura
  module Web
    module Router

      module MiddlewareChain
        module_function

        def short_circuit(middlewares, env, params)
          Array(middlewares).each do |raw|
            middleware = raw.is_a?(Class) ? raw.new : raw
            result = middleware.call(env, params)
            return result if rack_response?(result)
          end
          nil
        end

        def rack_response?(value)
          value.is_a?(Array) && value.size == 3 && value[0].is_a?(Integer)
        end
      end
    end
  end
end
