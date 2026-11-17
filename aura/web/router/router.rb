require_relative "route"
require_relative "matcher"
require_relative "param_schema"
require_relative "middleware_chain"
require_relative "file_router"
require_relative "api_router"
require_relative "../../i18n/locale_router"

module Aura
  module Web
    module Router
      class Router
        DEFAULT_REDIRECT_STATUS = 301

        attr_reader :routes, :file_router, :api_router, :middlewares,
                    :redirects, :rewrites, :locale_router

        def initialize
          @routes = []
          @file_router = nil
          @api_router = nil
          @middlewares = []
          @redirects = {}
          @rewrites = {}
          @locale_router = nil
        end

        def draw(&block)
          instance_eval(&block) if block
        end

        def route(map = nil, target = nil, **opts, &block)
          middleware = opts.delete(:middleware)

          if map.nil? && opts.keys.any? { |key| key.is_a?(String) }
            map = opts
            opts = {}
          end
          raise ArgumentError, "unknown options: #{opts.keys.inspect}" unless opts.empty?

          schema = block ? ParamSchema.build(&block) : nil

          if map.is_a?(Hash)
            map.each do |pattern, dest|
              @routes << Route.new(pattern, dest, param_schema: schema, middleware: middleware)
            end
          else
            @routes << Route.new(map, target || map, param_schema: schema, middleware: middleware)
          end
        end

        def redirect(map)
          map.each { |from, to| @redirects[from] = to }
          self
        end

        def rewrite(map)
          map.each { |from, to| @rewrites[from] = to }
          self
        end

        def use(*middlewares)
          @middlewares.concat(middlewares)
          self
        end

        def i18n(locales:, default: "en")
          @locale_router = Aura::I18n::LocaleRouter.new(locales: locales, default: default)
          self
        end

        def localize(path, locale)
          return path unless @locale_router

          @locale_router.localize(path, locale)
        end

        def files(root = "app/pages")
          @file_router = FileRouter.new(root)
        end

        def api(root = "app/api")
          @api_router = ApiRouter.new(root)
        end

        def resolve(path)
          path_only, query, fragment = Matcher.split(path)

          locale = nil
          if @locale_router
            locale, path_only = @locale_router.strip_prefix(path_only)
          end

          match = resolve_target(path_only)
          return nil unless match

          route, params = match
          route = route.dup
          route.query = query
          route.fragment = fragment
          route.locale = locale
          [route, params]
        end

        def resolve_api(path)
          @api_router&.resolve(path)
        end

        def middlewares_for(route)
          @middlewares + Array(route.middleware)
        end

        def run_middlewares(route, env, params = {})
          MiddlewareChain.short_circuit(middlewares_for(route), env, params)
        end

        def layout_chain(page_file)
          @file_router ? @file_router.layout_chain(page_file) : []
        end

        def error_file_for(page_file)
          @file_router&.error_file_for(page_file)
        end

        def loading_file_for(page_file)
          @file_router&.loading_file_for(page_file)
        end

        def not_found_file
          @file_router&.not_found_file
        end

        def static_pages
          @file_router ? @file_router.static_pages : []
        end

        def static_routes
          @file_router ? @file_router.static_routes : []
        end

        private

        def resolve_target(path)
          if (match = match_map(@redirects, path))
            template, params, status = match
            location = interpolate(template, params)
            return [Route.new(path, location, status: status, location: location), params]
          end

          if (match = match_map(@rewrites, path))
            template, params, = match
            inner = resolve_routes_or_files(interpolate(template, params))
            return nil unless inner

            route, inner_params = inner
            rewritten = Route.new(path, route.target, middleware: route.middleware,
                                                 param_schema: route.param_schema, rewrite: true)
            return [rewritten, inner_params]
          end

          resolve_routes_or_files(path)
        end

        def resolve_routes_or_files(path)
          @routes.each do |route|
            params = Matcher.match(route.pattern, path)
            next unless params
            next unless valid_params?(route, params)

            return [route, params]
          end

          @file_router&.resolve(path)
        end

        def valid_params?(route, params)
          schema = route.param_schema
          schema.nil? || schema.empty? || schema.valid?(params)
        end

        def match_map(map, path)
          map.each do |from, value|
            params = Matcher.match(from, path)
            next unless params

            template, status = normalise_destination(value)
            return [template, params, status]
          end
          nil
        end

        def normalise_destination(value)
          if value.is_a?(Hash)
            [value[:to] || value["to"], value[:status] || value["status"] || DEFAULT_REDIRECT_STATUS]
          else
            [value, DEFAULT_REDIRECT_STATUS]
          end
        end

        def interpolate(template, params)
          params.sort_by { |name, _| -name.to_s.length }.reduce(template.to_s) do |acc, (name, value)|
            acc.gsub(":#{name}", value.to_s)
          end
        end
      end
    end
  end
end
