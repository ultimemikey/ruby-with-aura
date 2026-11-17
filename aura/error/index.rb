require_relative "config/config"
require_relative "types/error_type"
require_relative "diagnostics/diagnostic"
require_relative "diagnostics/diagnostic_extractor"
require_relative "logger/logger"
require_relative "renderer/error_renderer"
require_relative "boundary/aura_boundary"
require_relative "exceptions"
require_relative "error_page"

require_relative "pages/generic_error_page"
require_relative "pages/route_not_found_page"
require_relative "pages/component_error_page"
require_relative "pages/dev_error_overlay_page"

require_relative "ui/error_badge"
require_relative "ui/error_card"
require_relative "ui/stack_trace_viewer"
require_relative "ui/code_frame"
require_relative "ui/suggestion_box"
require_relative "ui/dev_overlay_panel"

module Aura
  module Error
    def self.boundary
      Boundary::AuraBoundary
    end

    def self.renderer
      Renderer::ErrorRenderer
    end

    def self.logger
      Logger::Store
    end

  end
end

