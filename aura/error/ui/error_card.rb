module Aura
  module Error
    module UI
      class ErrorCard
        def self.render(title:, message:, badge_html:, code_frame_html:, suggestions_html:, stack_html:)
          <<~HTML
          <div class="aura-error-card">
            <div class="aura-error-card-header">
              <h1 class="aura-error-title">#{title}</h1>
              #{badge_html}
            </div>
            <pre class="aura-error-message">#{message}</pre>
            #{code_frame_html}
            #{suggestions_html}
            #{stack_html}
          </div>
          HTML
        end
      end
    end
  end
end

