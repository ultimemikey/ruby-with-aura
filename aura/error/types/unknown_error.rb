require_relative "error_type"

module Aura
  module Error
    module Types
      class UnknownError < ErrorType
        def initialize(message: nil, data: {}, cause: nil)
          super(code: :server_error, message: message, data: data, cause: cause)
        end
      end
    end
  end
end

