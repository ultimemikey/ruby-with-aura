require_relative "error_type"

module Aura
  module Error
    module Types
      class FileNotFound < ErrorType
        def initialize(message: nil, data: {}, cause: nil)
          super(code: Codes::FILE_NOT_FOUND, message: message, data: data, cause: cause)
        end
      end
    end
  end
end

