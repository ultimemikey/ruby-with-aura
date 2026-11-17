module Aura
  module Error
    module UI
      class StackTraceViewer
        def self.render(stack: [])
          return "" if stack.nil? || stack.empty?

          frames = stack.take(40).each_with_index.map do |line, i|
            open = i.zero? ? " open" : ""
            <<~HTML
            <details class="aura-error-frame"#{open}>
              <summary>#{escape_html(line.to_s)}</summary>
            </details>
            HTML
          end.join

          <<~HTML
          <section class="aura-error-section">
            <div class="aura-error-section-header">
              <span class="aura-error-section-title">Call Stack</span>
              <span class="aura-error-section-meta">#{stack.size} frames</span>
            </div>
            <div class="aura-error-stack">#{frames}</div>
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

