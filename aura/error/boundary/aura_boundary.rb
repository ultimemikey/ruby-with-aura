require_relative "../diagnostics/diagnostic_extractor"
require_relative "../logger/logger"
require_relative "../types/error_type"

module Aura
  module Error
    module Boundary
      class AuraBoundary
        def self.capture(exception, type_code:, context: {})

          code = type_code || :server_error

          diagnostic = Diagnostics::DiagnosticExtractor.extract(
            exception,
            type_code: code,
            context: context
          )

          Logger::Store.log(diagnostic, exception: exception)

          diagnostic
        end
      end
    end
  end
end

