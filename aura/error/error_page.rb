module Aura
  module Error
    class ErrorPage
      PAGES = {
        404 => { title: "404 — Page introuvable",  message: "La route demandée n'existe pas.",              color: "#fff" },
        500 => { title: "500 — Erreur serveur",     message: "Une erreur interne s'est produite.",           color: "#fff" },
        403 => { title: "403 — Accès refusé",       message: "Vous n'avez pas accès à cette ressource.",    color: "#fff" },
        422 => { title: "422 — Requête invalide",   message: "Les données envoyées sont incorrectes.",       color: "#fff" }
      }.freeze

      def self.render(status, path: nil)
        config  = PAGES[status] || { title: "#{status} — Erreur", message: "Une erreur est survenue.", color: "#fff" }
        title   = config[:title]
        message = config[:message]
        color   = config[:color]
        path_hint = path ? "<p class='path'>#{escape(path)}</p>" : ""

        <<~HTML
          <!DOCTYPE html>
          <html lang="fr">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Aura — #{escape(title)}</title>
            <style>
              *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

              body {
                background: #000;
                color: #fff;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
              }

              .page {
                text-align: center;
                padding: 40px 20px;
              }

              .code {
                font-size: 96px;
                font-weight: 800;
                color: #{color};
                opacity: 1;
                line-height: 1;
                letter-spacing: -4px;
                margin-bottom: 24px;
                font-family: inherit;
              }

              .title {
                font-size: 18px;
                font-weight: 600;
                color: #{color};
                margin-bottom: 12px;
                letter-spacing: 0.02em;
              }

              .message {
                font-size: 14px;
                color: #9ca3af;
                margin-bottom: 20px;
                line-height: 1.6;
              }

              .path {
                font-size: 12px;
                color: #fff;
                background: #1f1f1f;
                border: 1px solid #333;
                border-radius: 5px;
                padding: 8px 16px;
                display: inline-block;
                margin-bottom: 32px;
              }

              .brand {
                font-size: 10px;
                letter-spacing: 0.14em;
                color: #9ca3af;
                text-transform: uppercase;
              }
            </style>
          </head>
          <body>
            <div class="page">
              <div class="code">#{status}</div>
              <div class="title">#{escape(title)}</div>
              <div class="message">#{escape(message)}</div>
              #{path_hint}
              <div class="brand">Aura Framework</div>
            </div>
          </body>
          </html>
        HTML
      end

      private

      def self.escape(str)
        str.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      end
    end
  end
end