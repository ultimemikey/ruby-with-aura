module Aura
  module Web
    module Middleware

      module SecurityHeaders
        DEFAULTS = {
          "x-content-type-options"     => "nosniff",
          "x-frame-options"            => "SAMEORIGIN",
          "referrer-policy"            => "strict-origin-when-cross-origin",
          "permissions-policy"         => "geolocation=(), microphone=(), camera=()",
          "cross-origin-opener-policy" => "same-origin"
        }.freeze

        DEFAULT_CSP = [
          "default-src 'self'",
          "script-src 'self' 'unsafe-inline'",
          "style-src 'self' 'unsafe-inline'",
          "img-src 'self' data:",
          "font-src 'self' data:",
          "connect-src 'self'",
          "frame-ancestors 'self'",
          "base-uri 'self'",
          "form-action 'self'"
        ].join("; ").freeze

        def self.apply(headers, env: Aura.env, csp: nil)
          DEFAULTS.each { |key, value| headers[key] ||= value }
          headers["content-security-policy"] ||= (csp || DEFAULT_CSP)

          if env == "production"
            headers["strict-transport-security"] ||= "max-age=31536000; includeSubDomains"
          end

          headers
        end
      end
    end
  end
end
