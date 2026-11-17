require_relative "error_type"

module Aura
  module Error
    module Types
      class ImportError < ErrorType
        def initialize(message: nil, data: {}, cause: nil)
          super(code: Codes::IMPORT_ERROR, message: message, data: data, cause: cause)
        end
      end
    end
  end
end

