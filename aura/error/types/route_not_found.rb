require_relative "error_type"

module Aura
  module Error
    module Types
      class RouteNotFound < ErrorType
        def initialize(message: nil, data: {}, cause: nil)
          super(code: Codes::ROUTE_NOT_FOUND, message: message, data: data, cause: cause)
        end
      end
    end
  end
end

