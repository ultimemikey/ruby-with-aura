require_relative "error_type"

module Aura
  module Error
    module Types
      class HydrationError < ErrorType
        def initialize(message: nil, data: {}, cause: nil)
          super(code: Codes::HYDRATION_ERROR, message: message, data: data, cause: cause)
        end
      end
    end
  end
end

