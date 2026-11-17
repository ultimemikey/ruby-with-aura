module Aura
  module Error
    module Types
      class ErrorType < StandardError
        attr_reader :code, :data

        def initialize(code:, message: nil, data: {}, cause: nil)
          @code = code
          @data = data || {}
          super(message || code.to_s)
          set_backtrace(cause.backtrace) if cause && cause.backtrace
        end
      end

      module Codes
        ROUTE_NOT_FOUND = :route_not_found
        COMPONENT_NOT_FOUND = :component_not_found
        FILE_NOT_FOUND = :file_not_found
        IMPORT_ERROR = :import_error
        SYNTAX_ERROR = :syntax_error
        SERVER_ERROR = :server_error
        STATE_ERROR = :state_error
        CONFIG_ERROR = :config_error
        HYDRATION_ERROR = :hydration_error
      end
    end
  end
end

