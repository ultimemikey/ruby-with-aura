module Aura
  module Web
    module Server
      class Response
        attr_accessor :status, :headers, :body

        def initialize(body = "", status = 200, headers = {})
          @body = body
          @status = status
          @headers = { "content-type" => "text/html; charset=utf-8" }.merge(headers)
        end

        def write(content)
          @body += content
        end

        def stream(body)
          @streaming = true
          @body = body
        end

        def streaming?
          @streaming ? true : false
        end

        def finish
          return [@status, @headers, @body] if streaming?

          [@status, @headers, [@body]]
        end
      end
    end
  end
end
