require_relative "error_type"

module Aura
  module Error
    module Types
      class ConfigError < ErrorType
        def initialize(message: nil, data: {}, cause: nil)
          super(code: Codes::CONFIG_ERROR, message: message, data: data, cause: cause)
        end
      end
    end
  end
end

