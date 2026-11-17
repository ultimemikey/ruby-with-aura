module Aura
  module Error
    module UI
      class CodeFrame
        def self.render(file:, line:)
          src = safe_read(file)
          return "" unless src

          lines = src.lines
          target = line.to_i
          start = [target - 5, 1].max
          end_line = [target + 5, lines.length].min
          location = "#{file}:#{target}"

          snippet = (start..end_line).map do |i|
            raw = lines[i - 1].to_s.chomp
            cls = i == target ? "aura-error-code-line is-target" : "aura-error-code-line"
            "<div class='#{cls}'><span class='aura-error-code-no'>#{i}</span><code>#{escape_html(raw)}</code></div>"
          end.join

          <<~HTML
          <section class="aura-error-section">
            <div class="aura-error-section-header">
              <span class="aura-error-section-title">Source</span>
              <span class="aura-error-section-meta">#{escape_html(location)}</span>
            </div>
            <div class="aura-error-code-frame">#{snippet}</div>
          </section>
          HTML
        end

        def self.safe_read(path)
          return nil unless path && File.file?(path)
          File.read(path, encoding: "utf-8")
        rescue
          nil
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

