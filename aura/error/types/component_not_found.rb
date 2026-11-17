require_relative "error_type"

module Aura
  module Error
    module Types
      class ComponentNotFound < ErrorType
        def initialize(message: nil, data: {}, cause: nil)
          super(code: Codes::COMPONENT_NOT_FOUND, message: message, data: data, cause: cause)
        end
      end
    end
  end
end

