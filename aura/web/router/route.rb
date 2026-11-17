module Aura
  module Web
    module Router

      class Route
        attr_reader :pattern, :target, :param_schema, :middleware, :status, :location
        attr_accessor :query, :fragment, :locale

        def initialize(pattern, target, param_schema: nil, middleware: nil,
                       status: nil, location: nil, rewrite: false)
          @pattern = pattern
          @target = target
          @param_schema = param_schema
          @middleware = Array(middleware)
          @status = status
          @location = location
          @rewrite = rewrite
          @query = {}
          @fragment = nil
          @locale = nil
        end

        def redirect?
          !@location.nil?
        end

        def rewrite?
          @rewrite == true
        end
      end
    end
  end
end
