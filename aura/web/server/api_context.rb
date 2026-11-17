require "json"

module Aura
  module Web
    module Server

      class ApiContext
        def initialize(request, params)
          @request  = request
          @params   = params || {}
          @handlers = {}
        end

        def self.load(file, request, params)
          ctx = new(request, params)
          ctx.instance_eval(::File.read(file, encoding: "utf-8"), file)
          ctx
        end

        def params   = @params
        def request  = @request
        def query    = @request.params
        def body     = @request.json_body

        def get(&block)    = @handlers[:GET] = block
        def post(&block)   = @handlers[:POST] = block
        def put(&block)    = @handlers[:PUT] = block
        def patch(&block)  = @handlers[:PATCH] = block
        def delete(&block) = @handlers[:DELETE] = block

        def json(obj = nil, status: 200, **extra)
          obj = extra if obj.nil? && !extra.empty?
          [status, { "content-type" => "application/json" }, [::JSON.generate(obj)]]
        end

        def text(str, status: 200)
          [status, { "content-type" => "text/plain; charset=utf-8" }, [str.to_s]]
        end

        def no_content
          [204, {}, []]
        end

        def handles?(method)
          @handlers.key?(method.to_s.upcase.to_sym)
        end

        def allowed_methods
          @handlers.keys.map(&:to_s)
        end

        def dispatch(method)
          handler = @handlers[method.to_s.upcase.to_sym]
          return nil unless handler

          result = instance_exec(&handler)
          result.is_a?(::Array) ? result : json(result)
        end
      end
    end
  end
end
