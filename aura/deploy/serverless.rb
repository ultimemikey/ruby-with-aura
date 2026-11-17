require "json"
require "uri"
require "stringio"

module Aura
  module Deploy

    module Serverless
      DEFAULT_CACHE = "public, max-age=0, must-revalidate"
      HEALTH_PATH   = "/_aura/health"

      def self.handler(rack_app)
        lambda do |event, _context = nil|
          status, headers, body = rack_app.call(rack_env(event))

          {
            statusCode: status,
            headers: headers || {},
            body: collect_body(body),
            isBase64Encoded: false
          }
        end
      end

      def self.rack_env(event)
        event   = {} unless event.is_a?(Hash)
        method  = event["httpMethod"] || dig_http(event, "method") || "GET"
        path    = event["path"] || event["rawPath"] || dig_http(event, "path") || "/"
        query   = query_string(event)
        headers = event["headers"].is_a?(Hash) ? event["headers"] : {}
        body    = decode_body(event["body"], event["isBase64Encoded"])

        env = {
          "REQUEST_METHOD"    => method.to_s.upcase,
          "SCRIPT_NAME"       => "",
          "PATH_INFO"         => path.to_s.empty? ? "/" : path.to_s,
          "QUERY_STRING"      => query,
          "SERVER_NAME"       => "localhost",
          "SERVER_PORT"       => "443",
          "SERVER_PROTOCOL"   => "HTTP/1.1",
          "rack.version"      => [1, 3],
          "rack.url_scheme"   => "https",
          "rack.input"        => StringIO.new(body),
          "rack.errors"       => StringIO.new,
          "rack.multithread"  => false,
          "rack.multiprocess" => false,
          "rack.run_once"     => true,
          "CONTENT_LENGTH"    => body.bytesize.to_s
        }

        headers.each { |k, v| apply_header(env, k.to_s, v) }
        env
      end

      def self.netlify_config(publish: "dist", command: nil, function: nil)
        command  ||= "bundle install && bundle exec ruby run export"
        function ||= "/.netlify/functions/aura"

        <<~TOML
          [build]
            command = "#{command}"
            publish = "#{publish}"

          [functions]
            directory = "netlify/functions"

          [[redirects]]
            from = "/*"
            to = "#{function}"
            status = 200

          [[headers]]
            for = "/assets/*"
            [headers.values]
              cache-control = "public, max-age=31536000, immutable"

          [[headers]]
            for = "/_aura/*"
            [headers.values]
              cache-control = "no-store"
        TOML
      end

      def self.vercel_config(build: "config.ru", use: "vercel-ruby@2")
        {
          "version" => 2,
          "builds" => [
            { "src" => build, "use" => use }
          ],
          "routes" => [
            { "src" => "/assets/(.*)", "headers" => { "cache-control" => "s-maxage=31536000, immutable" } },
            { "src" => "/_aura/(.*)",  "headers" => { "cache-control" => "no-store" } },
            { "src" => "/(.*)",        "dest" => build }
          ]
        }
      end

      def self.edge_adapter(rack_app)
        lambda do |env|
          if env["PATH_INFO"] == HEALTH_PATH
            payload = JSON.generate({ status: "ok" })
            return [200, { "content-type" => "application/json", "cache-control" => "no-store" }, [payload]]
          end

          status, headers, body = rack_app.call(env)
          headers = (headers || {}).dup
          unless headers.keys.any? { |k| k.to_s.downcase == "cache-control" }
            headers["Cache-Control"] = DEFAULT_CACHE
          end

          [status, headers, body]
        end
      end

      def self.dig_http(event, key)
        ctx = event["requestContext"]
        return nil unless ctx.is_a?(Hash)

        http = ctx["http"]
        return nil unless http.is_a?(Hash)

        http[key]
      end

      def self.query_string(event)
        raw = event["rawQueryString"].to_s
        return raw unless raw.empty?

        params = event["queryStringParameters"]
        return "" unless params.is_a?(Hash)

        URI.encode_www_form(params.reject { |_k, v| v.nil? })
      rescue ArgumentError
        ""
      end

      def self.decode_body(raw, encoded)
        return "" if raw.nil?

        encoded ? raw.to_s.unpack1("m") : raw.to_s
      end

      def self.apply_header(env, name, value)
        case name.downcase
        when "content-type"   then env["CONTENT_TYPE"]   = value.to_s
        when "content-length" then env["CONTENT_LENGTH"] = value.to_s
        when "host"
          env["SERVER_NAME"] = value.to_s
        else
          env["HTTP_#{name.upcase.tr('-', '_')}"] = value.to_s
        end
      end

      def self.collect_body(body)
        return "" if body.nil?

        buf = String.new(encoding: Encoding::BINARY)
        if body.respond_to?(:each)
          body.each { |chunk| buf << chunk.to_s.b }
        else
          buf << body.to_s.b
        end

        body.close if body.respond_to?(:close)
        buf
      end
    end
  end
end
