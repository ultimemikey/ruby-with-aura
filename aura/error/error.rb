require_relative "exceptions"
require_relative "error_page"
require_relative "diagnostics/diagnostic"
require_relative "diagnostics/diagnostic_extractor"
require_relative "boundary/aura_boundary"
require_relative "logger/logger"
require_relative "renderer/error_renderer"

module Aura
  module Error

    def self.handle(exception, env: "development")
      type_code  = map_exception_to_type_code(exception)
      diagnostic = Boundary::AuraBoundary.capture(exception, type_code: type_code)

      if env == "development"
        Renderer::ErrorRenderer.render(diagnostic)
      else
        ErrorPage.render(500)
      end
    end

    def self.map_exception_to_type_code(exception)
      case exception
      when PageNotFoundError
        :route_not_found
      when ComponentNotFoundError
        :component_not_found
      when LayoutNotFoundError
        :layout_not_found
      when AssetNotFoundError, Errno::ENOENT
        :file_not_found
      when IncludeNotFoundError
        :import_error
      when SyntaxError
        :syntax_error
      when SecurityError
        :security_error
      else
        :server_error
      end
    end
  end
end