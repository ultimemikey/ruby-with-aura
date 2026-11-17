module Aura
  module Error
    module UI
      class SuggestionBox
        def self.render(suggestions: [])
          return "" if suggestions.nil? || suggestions.empty?

          items = suggestions.map { |s| "<li>#{escape_html(s)}</li>" }.join
          <<~HTML
          <section class="aura-error-section">
            <div class="aura-error-section-header">
              <span class="aura-error-section-title">Possible fixes</span>
            </div>
            <ul class="aura-error-suggestions">#{items}</ul>
          </section>
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

