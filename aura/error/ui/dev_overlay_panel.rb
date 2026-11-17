module Aura
  module Error
    module UI
      class DevOverlayPanel
        def self.render(diagnostic:)
          file = diagnostic.file ? diagnostic.file.to_s : "Unknown source"
          line = diagnostic.line ? ":#{diagnostic.line}" : ""
          location = "#{file}#{line}"

          <<~HTML
          <div class="aura-error-dev-overlay" role="alert">
            <div class="aura-error-dev-overlay-inner">
              <span class="aura-error-dev-overlay-label">Runtime Error</span>
              <span class="aura-error-dev-overlay-meta">#{escape_html(location)}</span>
            </div>
          </div>
          HTML
        end

        def self.escape_html(str)
          str.to_s
             .gsub('&', '&amp;')
             .gsub('<', '<')
             .gsub('>', '>')
             .gsub('"', '"')
             .gsub("'", '&#39;')
        end
      end
    end
  end
end

