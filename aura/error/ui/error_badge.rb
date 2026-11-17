module Aura
  module Error
    module UI
      class ErrorBadge
        def self.render(type_code:)
          code = type_code.to_s
          "<span class=\"aura-error-badge\" data-type=\"#{escape(code)}\">#{escape(code)}</span>"
        end

        def self.escape(str)
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

