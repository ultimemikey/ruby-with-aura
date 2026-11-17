require_relative "error_type"

module Aura
  module Error
    module Types
      class SyntaxErrorType < ErrorType
        def initialize(message: nil, data: {}, cause: nil)
          super(code: Codes::SYNTAX_ERROR, message: message, data: data, cause: cause)
        end
      end
    end
  end
end

