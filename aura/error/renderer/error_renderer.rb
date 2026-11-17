require_relative "../config/config"
require_relative "../pages/generic_error_page"
require_relative "../pages/dev_error_overlay_page"
require "json"

module Aura
  module Error
    module Renderer
      class ErrorRenderer
        PROJECT_ROOT = File.expand_path(Dir.pwd).freeze

        def self.render(diagnostic, config: Config::AuraErrorConfig.new)
          return render_prod(diagnostic) unless config.dev?

          diagnostics = [diagnostic].compact
          Pages::DevErrorOverlayPage.render(
            diagnostics: diagnostics,
            index: 0,
            config: config,
            version: aura_version,
            env: aura_env
          )
        end

        def self.render_prod(diagnostic)
          title = esc(diagnostic&.title || "Server Error")
          message = esc(diagnostic&.message || "An unexpected error occurred.")
          inner = <<~HTML
            <div class="aura-error-card">
              <div class="aura-error-card-header"><h1 class="aura-error-title">#{title}</h1></div>
              <pre class="aura-error-message">#{message}</pre>
            </div>
          HTML
          Pages::GenericErrorPage.render(diagnostic: diagnostic, inner: inner)
        end

        def self.esc(str)
          str.to_s
            .gsub("&", "&amp;")
            .gsub("<", "&lt;")
            .gsub(">", "&gt;")
            .gsub('"', "&quot;")
            .gsub("'", "&#39;")
        end

        def self.relative_path(path)
          return nil if path.nil? || path.to_s.empty?
          p = path.to_s
          if p.start_with?(PROJECT_ROOT + File::SEPARATOR)
            p.delete_prefix(PROJECT_ROOT + File::SEPARATOR)
          elsif p.start_with?(PROJECT_ROOT)
            p.delete_prefix(PROJECT_ROOT).sub(%r{^/}, "")
          else
            p
          end
        end

        def self.display_location(file, line, column = nil)
          return "Unknown source" unless file
          loc = relative_path(file).to_s
          loc += ":#{line}" if line
          loc += ":#{column}" if column
          loc
        end

        def self.aura_version
          defined?(::Aura::VERSION) ? ::Aura::VERSION.to_s : "dev"
        rescue
          "dev"
        end

        def self.aura_env
          if defined?(::Aura) && ::Aura.respond_to?(:env)
            ::Aura.env.to_s
          else
            (ENV["AURA_ENV"] || ENV["RACK_ENV"] || "development").to_s
          end
        rescue
          "development"
        end
      end
    end
  end
end
