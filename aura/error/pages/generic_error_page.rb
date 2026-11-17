module Aura
  module Error
    module Pages
      class GenericErrorPage
        def self.render(diagnostic:, inner:)
          title = escape_html(diagnostic&.title || "Error")
          <<~HTML
          <!doctype html>
          <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>#{title}</title>
            <style>#{base_css}</style>
          </head>
          <body><div class="aura-error-shell">#{inner}</div></body>
          </html>
          HTML
        end

        def self.base_css
          <<~'CSS'
          :root{--bg:#000;--surface:#0a0a0a;--border:#252525;--text:#ededed;--muted:#a1a1aa;--accent:#f87171}
          *{box-sizing:border-box} html,body{margin:0;padding:0}
          body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;background:var(--bg);color:var(--text);line-height:1.5}
          .aura-error-shell{max-width:960px;margin:0 auto;padding:40px 20px 80px}
          .aura-error-title{margin:0;font-size:13px;font-weight:600;color:var(--accent);letter-spacing:.04em;text-transform:uppercase}
          .aura-error-message{margin:12px 0 0;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;font-size:22px;font-weight:600;white-space:pre-wrap;word-break:break-word}
          CSS
        end

        def self.escape_html(str)
          str.to_s.gsub("&","&amp;").gsub("<","&lt;").gsub(">","&gt;").gsub('"',"&quot;").gsub("'","&#39;")
        end
      end

      class RouteNotFoundPage
        def self.render(diagnostic:, inner:)
          GenericErrorPage.render(diagnostic: diagnostic, inner: inner)
        end
      end

      class ComponentErrorPage
        def self.render(diagnostic:, inner:)
          GenericErrorPage.render(diagnostic: diagnostic, inner: inner)
        end
      end

      class GenericErrorPageFacade
        def self.render(diagnostic:, inner:, overlay_html: nil)
          body = "#{overlay_html}#{inner}"
          GenericErrorPage.render(diagnostic: diagnostic, inner: body)
        end
      end
    end
  end
end
