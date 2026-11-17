require_relative "request"
require_relative "response"
require_relative "api_context"
require_relative "../../core/loader/page_loader"
require_relative "../../core/renderer/renderer"
require_relative "../../core/cache/store"
require_relative "../../dev/dev"
require_relative "../../i18n/i18n"
require_relative "../middleware/security_headers"
require_relative "../middleware/rate_limiter"
require_relative "../router/param_schema"
require_relative "../seo/sitemap"
require_relative "session_store"
require_relative "live_reload_watcher"
require "securerandom"
require "digest"
require "openssl"
require "json"
require "uri"
require "ipaddr"

module Aura

  module Web
    module Server
      class Server
        attr_reader :router, :rate_limiter

        DEFAULT_SESSION_SECRET = "aura-default-session-secret".freeze

        def initialize(router, session_store: nil, rate_limiter: nil, session_ttl: nil, session_secret: nil,
                       metrics: nil, tracer: nil, logger: nil, project_root: Dir.pwd,
                       trusted_proxies: ENV.fetch("AURA_TRUSTED_PROXIES", ""))
          @router         = router
          @session_store  = session_store || SessionStore.build
          max_rate_buckets = ENV.fetch("AURA_RATE_LIMITER_MAX_BUCKETS", Middleware::RateLimiter::DEFAULT_MAX_BUCKETS.to_s).to_i
          @rate_limiter   = rate_limiter || Middleware::RateLimiter.new(max_buckets: max_rate_buckets)
          @trusted_proxies = normalize_trusted_proxies(trusted_proxies)
          @session_ttl    = (session_ttl || ENV.fetch("AURA_SESSION_TTL", "3600")).to_i
          if Aura.env == "production" && ENV["AURA_SESSION_SECRET"].nil?
            raise ArgumentError, "AURA_SESSION_SECRET must be set in production"
          end
          configured_secret = session_secret || ENV["AURA_SESSION_SECRET"]
          @session_secret = configured_secret || DEFAULT_SESSION_SECRET
          @project_root   = File.realpath(project_root)
          @static_paths  = normalize_static_paths(Aura::Config.load(@project_root).static_paths)
          if Aura.env == "production" && @session_secret.bytesize < 32
            raise ArgumentError, "AURA_SESSION_SECRET must be at least 32 bytes in production"
          end
          @refreshing     = {}
          @refresh_mutex  = Mutex.new

          @metrics        = metrics || ::Aura::Dev::Metrics.shared
          @tracer         = tracer  || ::Aura::Dev::Tracer.shared
          @logger         = logger  || ::Aura::Dev::Logger.shared
          @tracing        = Aura.env != "production"
        end

        def call(env)
          req = Request.new(env, trusted_proxies: @trusted_proxies)
          started = monotonic
          @metrics.increment("aura.requests")
          @logger.debug("aura.request.start", method: req.method, path: req.path)

          status, headers, body = trace_request(req) { handle(req) }

          @metrics.timing("aura.request.duration", monotonic - started)
          @logger.debug("aura.request", method: req.method, path: req.path, status: status)

          Middleware::SecurityHeaders.apply(headers, env: Aura.env)

          if status == 200 && req.method == "GET" && html_response?(headers) && body.is_a?(::Array)
            html = flatten_body(body)
            etag = %("#{::Digest::SHA256.hexdigest(html)[0, 32]}")
            headers["etag"] = etag
            if req.header("if-none-match").to_s.split(",").map(&:strip).include?(etag)
              return [304, { "etag" => etag }, []]
            end
          end

          [status, headers, body]
        end

        private

        def handle(req)
          res = Response.new

          session_id = read_session_token(req.cookies["aura_session_id"])
          session_id ||= @session_store.generate_id
          session_data = @session_store.read(session_id)

          res.headers["set-cookie"] = cookie_header(sign_session_id(session_id))

          session_data[:aura_csrf] ||= SecureRandom.base64(32)

          pending_flash = flash_keys(session_data)

          if req.path == "/_aura/health"
            return json_response(200, status: "ok", version: Aura::VERSION, env: Aura.env)
          end

          if req.method == "GET" && req.path == "/robots.txt" && !static_file?(req.path)
            return render_robots(req)
          end
          if req.method == "GET" && req.path == "/sitemap.xml" && !static_file?(req.path)
            return render_sitemap(req)
          end

          if (limited = rate_limit_response(req, session_id))
            return limited
          end

          if req.path == "/_aura/live_reload"
            return [404, { "content-type" => "text/plain; charset=utf-8" }, ["Not Found"]] if Aura.env == "production"

            return handle_live_reload(req)
          end

          if req.path == "/_aura/client.js"
            return serve_client_runtime
          end

          if req.path == "/_aura/defer" && req.method == "GET"
            return handle_defer(req, session_data)
          end

          if req.path == "/api" || req.path.start_with?("/api/")
            return handle_api(req)
          end

          if req.path == "/_aura/action" && req.method == "POST"
            return handle_reactive_action(req, session_id, session_data)
          end

          if static_file?(req.path)
            return serve_static_file(req.path)
          end

          route_match = @router.resolve(req.path)
          unless route_match
            return render_not_found(req)
          end

          route, path_params = route_match
          if (middleware_response = @router.run_middlewares(route, req.headers, path_params))
            return middleware_response
          end

          page_path = find_page_file(route.target)
          return render_page_error(req, nil) unless page_path

          cookies_data = req.cookies

          begin

            layout_files = @router.layout_chain(page_path)
            loading_file = @router.loading_file_for(page_path)

            run_unmount(req, session_data, page_path)

            catalog, loc = locale_catalog(req, session_data)

            doc, parser = Core::Loader::PageLoader.load(
              page_path, session_data, cookies_data, path_params,
              layout_files: layout_files,
              loading_file: loading_file,
              i18n: catalog,
              locale: loc,
              query: req.query,
              fragment: req.fragment
            )

            return render_not_found(req) unless valid_param_types?(doc, path_params)

            session_data[:aura_params] = path_params

            doc.define_singleton_method(:csrf_token) { session_data[:aura_csrf] }

            if (entry = doc.handlers[:mount])
              mount_handler = entry.is_a?(Hash) ? entry[:handler] : entry
              mount_handler.call if mount_handler
            end

            page_cache = doc.page_cache
            cache_key = page_cache ? page_cache_key(req.path) : nil
            html = nil

            if page_cache
              entry = read_page_cache_entry(cache_key)
              if entry
                if page_cache_fresh?(entry, page_cache[:ttl])
                  html = entry[:html]
                elsif page_cache[:swr]

                  html = entry[:html]
                  schedule_page_refresh(req, page_path, session_data, page_cache, cache_key)
                end
              end
            end

            streamed = nil

            if html.nil?

              if page_cache.nil? && streaming_candidate?(doc)
                streamed = Core::Renderer::Renderer.render_stream(doc, parser)
              else

                html = Core::Renderer::Renderer.render(doc, parser)
              end

              if (redirect = redirect_from(parser))
                session_data[:aura_current_page] = page_path
                session_data[:aura_current_route] = req.path
                @session_store.write(session_id, session_data)
                return redirect_response(redirect, session_id)
              end

              write_page_cache(cache_key, html, page_cache[:ttl]) if page_cache && html

              session_data[:aura_state] = parser.extract_state
            end

            consume_flash!(session_data, pending_flash)

            session_data[:aura_current_page] = page_path
            session_data[:aura_current_route] = req.path
            @session_store.write(session_id, session_data)

            res.headers["set-cookie"] = merge_cookies(res.headers["set-cookie"], parser_cookies(parser))

            if streamed
              res.stream(streamed)
            else
              res.write(html)
            end
            res.finish
          rescue => e

            error_file = @router.error_file_for(page_path)
            raise unless error_file

            render_page_error(req, error_file, e)
          end
        rescue => e
          html = Aura::Error.handle(e, env: Aura.env)
          res.status = 500
          res.write(html)
          res.finish
        end

        def handle_reactive_action(req, session_id, session_data)
          page_path = session_data[:aura_current_page]
          state_data = session_data[:aura_state] || {}

          action = parse_action_request(req)

          expected = session_data[:aura_csrf]
          provided = action[:csrf]
          unless expected && provided && expected.bytesize == provided.bytesize && provided.bytesize > 0 && secure_compare(expected, provided)
            return [403, { "content-type" => "text/plain" }, ["Forbidden: CSRF"]]
          end

          unless page_path && File.file?(page_path)
            return [400, { "content-type" => "text/plain" }, ["Bad Request: No page loaded in session"]]
          end

          route_path = session_data[:aura_current_route]
          route_match = route_path && @router.resolve(route_path)
          return [400, { "content-type" => "text/plain" }, ["Bad Request: No route loaded in session"]] unless route_match

          route, route_params = route_match
          if (middleware_response = @router.run_middlewares(route, req.headers, route_params))
            return middleware_response
          end

          catalog, loc = locale_catalog(req, session_data)

          route_params = session_data[:aura_params].is_a?(::Hash) ? session_data[:aura_params] : route_params
          action_params = route_params.empty? ? req.params : route_params.merge(req.params)
          doc, parser = Core::Loader::PageLoader.load(
            page_path, session_data, req.cookies, action_params,
            layout_files: @router.layout_chain(page_path),
            loading_file: @router.loading_file_for(page_path),
            i18n: catalog,
            locale: loc,
            query: req.query,
            fragment: req.fragment
          )

          unless valid_param_types?(doc, action_params)
            return [400, { "content-type" => "text/plain" }, ["Bad Request: invalid route params"]]
          end

          parser.inject_state(state_data)

          handler_name = action[:handler]
          value = action[:value]
          form_data = action[:form]

          action_entry = nil

          if handler_name.to_s == "__aura_bind"

            field = action[:field].to_s
            parser.inject_state(field => value) unless field.empty?
          else

            action_entry = doc.handlers[handler_name.to_sym]
            handler = action_entry.is_a?(Hash) ? action_entry[:handler] : nil
            is_public = action_entry.is_a?(Hash) ? action_entry[:public] : false

            unless handler && is_public
              return [403, { "content-type" => "text/plain" }, ["Forbidden: handler not public"]]
            end

            payload = form_data || value
            handler.call(payload)

            if action_entry.is_a?(Hash) && action_entry[:revalidate]
              keys = Array(action_entry[:revalidate]).map { |k| :"loader:#{k}" }
              Core::Cache::Store.shared.revalidate(*keys)
              parser.clear_loader_cache! if parser.respond_to?(:clear_loader_cache!)
            end
          end

          if (entry = doc.handlers[:update])
            update_handler = entry.is_a?(Hash) ? entry[:handler] : entry
            update_handler.call if update_handler
          end

          redirect = redirect_from(parser)

          csrf_val = SecureRandom.base64(32)
          session_data[:aura_csrf] = csrf_val
          doc.define_singleton_method(:csrf_token) { csrf_val }

          if redirect

            session_data[:aura_state] = parser.extract_state
            @session_store.write(session_id, session_data)
            new_id = rotate_session(session_id)
            return [303, {
              "location"      => redirect,
              "set-cookie"    => cookie_header(sign_session_id(new_id)),
              "x-csrf-token"  => csrf_val
            }, []]
          end

          html = Core::Renderer::Renderer.render(doc, parser)

          state_patch = patch_header(parser.state_diff(state_data))
          optimistic  = patch_header(parser.optimistic)

          session_data[:aura_state] = parser.extract_state

          consume_flash!(session_data, flash_keys(session_data))
          @session_store.write(session_id, session_data)

          new_id = rotate_session(session_id)

          headers = {
            "content-type" => "text/html",
            "x-csrf-token" => csrf_val,
            "set-cookie"   => cookie_header(sign_session_id(new_id))
          }

          headers["set-cookie"] = merge_cookies(headers["set-cookie"], parser_cookies(parser))
          headers["x-aura-state"] = state_patch if state_patch
          headers["x-aura-optimistic"] = optimistic if optimistic
          [200, headers, [html]]
        rescue => e
          render_action_error(req, e, session_id, session_data)
        end

        def handle_api(req)
          sub = req.path.sub(%r{\A/api(?=/|\z)}, "")
          sub = "/" if sub.empty?

          match = @router.resolve_api(sub)
          return json_response(404, error: "Not Found") unless match

          route, params = match
          if (middleware_response = @router.run_middlewares(route, req.headers, params))
            return middleware_response
          end
          file = find_page_file(route.target)
          return json_response(500, error: "API route handler missing") unless file

          ctx = ApiContext.load(file, req, params)
          unless ctx.handles?(req.method)
            status, headers, body = json_response(405, error: "Method Not Allowed")
            headers["allow"] = ctx.allowed_methods.join(", ")
            return [status, headers, body]
          end

          ctx.dispatch(req.method) || json_response(204)
        rescue => e
          payload = { error: "Internal Server Error" }
          payload[:message] = e.message if Aura.env != "production"
          json_response(500, payload)
        end

        def json_response(status, payload)
          [status, { "content-type" => "application/json" }, [::JSON.generate(payload)]]
        end

        def html_response?(headers)
          (headers["content-type"] || "").include?("text/html")
        end

        def flatten_body(body)
          body.respond_to?(:join) ? body.join : body.to_s
        end

        def valid_param_types?(doc, params)
          types = doc.respond_to?(:param_types) ? doc.param_types : nil
          return true if types.nil? || types.empty?

          schema = Router::ParamSchema.new
          types.each { |name, spec| schema.param(name, type: spec[:type], required: spec[:required]) }
          schema.valid?(params)
        end

        def patch_header(values)
          return nil if values.nil? || values.empty?

          ::JSON.generate(values)
        rescue ::StandardError
          nil
        end

        def parser_cookies(parser)
          queued = parser.respond_to?(:cookies_out) ? parser.cookies_out : nil
          return [] unless queued.is_a?(::Hash)

          queued.map { |name, spec| cookie_string(name, spec) }
        end

        def cookie_string(name, spec)
          value   = spec.is_a?(::Hash) ? spec[:value] : spec
          max_age = spec.is_a?(::Hash) ? spec[:max_age] : nil
          secure  = Aura.env == "production" ? "; Secure" : ""

          parts = [
            "#{name}=#{::URI.encode_www_form_component(value.to_s)}",
            "Path=/",
            "SameSite=Lax#{secure}"
          ]
          parts << "Max-Age=#{max_age.to_i}" if max_age
          parts.join("; ")
        end

        def merge_cookies(existing, extra)
          return existing if extra.nil? || extra.empty?

          existing.nil? || existing.empty? ? extra : [existing, *extra]
        end

        def streaming_candidate?(doc)
          doc.respond_to?(:suspense_blocks) && !doc.suspense_blocks.empty?
        end

        def rate_limit_response(req, session_id)
          key =
            if req.path == "/_aura/action" && req.method == "POST"
              "action:#{session_id}"
            elsif req.path == "/api" || req.path.start_with?("/api/")
              "api:#{req.ip}"
            end

          return nil unless key

          allowed, retry_after = @rate_limiter.allow?(key)
          return nil if allowed

          [429,
           { "content-type" => "application/json", "retry-after" => retry_after.to_s },
           [::JSON.generate(error: "Too Many Requests")]]
        end

        def normalize_trusted_proxies(value)
          entries = value.is_a?(String) ? value.split(",") : Array(value)
          entries.filter_map do |entry|
            text = entry.to_s.strip
            next if text.empty?

            IPAddr.new(text)
          rescue IPAddr::InvalidAddressError
            raise ArgumentError, "Invalid trusted proxy address or CIDR: #{entry.inspect}"
          end.freeze
        end

        def locale_catalog(req, session_data)
          locale = I18n::Catalog.negotiate(
            root: @project_root,
            explicit: req.params["lang"],
            cookie: req.cookies["aura_locale"],
            accept_language: req.header("accept-language")
          )
          session_data[:aura_locale] = locale
          [I18n::Catalog.new(@project_root, locale), locale]
        end

        def run_unmount(req, session_data, new_page)
          return unless req.header("x-aura-navigate")

          previous = session_data[:aura_current_page]
          return if previous.nil? || previous == new_page || !File.file?(previous)

          doc, = Core::Loader::PageLoader.load(previous, session_data, req.cookies, {})
          entry = doc.handlers[:unmount]
          handler = entry.is_a?(Hash) ? entry[:handler] : entry
          handler.call if handler
        rescue
          nil
        end

        def render_action_error(req, exception, session_id, session_data)
          page_path = session_data[:aura_current_page]

          if page_path && File.file?(page_path)
            begin
              catalog, loc = locale_catalog(req, session_data)
              doc, parser = Core::Loader::PageLoader.load(
                page_path, session_data, req.cookies, {},
                layout_files: @router.layout_chain(page_path),
                loading_file: @router.loading_file_for(page_path),
                i18n: catalog,
                locale: loc
              )
              parser.inject_state(session_data[:aura_state] || {})

              entry = doc.handlers[:error]
              handler = entry.is_a?(Hash) ? entry[:handler] : entry

              if handler
                handler.call(exception)
                html = Core::Renderer::Renderer.render(doc, parser)
                session_data[:aura_state] = parser.extract_state
                @session_store.write(session_id, session_data)
                return [200, { "content-type" => "text/html; charset=utf-8" }, [html]]
              end
            rescue

            end
          end

          html = Aura::Error.handle(exception, env: Aura.env)
          [500, { "content-type" => "text/html; charset=utf-8" }, [html]]
        end

        def render_robots(_req)
          body = SEO::Sitemap.robots(base_url: site_base_url)
          [200, { "content-type" => "text/plain; charset=utf-8", "cache-control" => "public, max-age=3600" }, [body]]
        end

        def render_sitemap(_req)
          body = SEO::Sitemap.render(@router.static_routes, base_url: site_base_url)
          [200, { "content-type" => "application/xml; charset=utf-8", "cache-control" => "public, max-age=3600" }, [body]]
        end

        def site_base_url
          ENV["AURA_SITE_URL"] ||
            Aura::Config.load(@project_root).data["siteUrl"] ||
            "http://localhost:#{ENV.fetch('PORT', 3000)}"
        end

        def render_not_found(req)
          file = @router.not_found_file
          if file
            begin
              doc, parser = Core::Loader::PageLoader.load(file, {}, req.cookies, {})
              html = Core::Renderer::Renderer.render(doc, parser)
              return [404, { "content-type" => "text/html; charset=utf-8" }, [html]]
            rescue

            end
          end

          [404, { "content-type" => "text/html; charset=utf-8" },
           [Aura::Error::ErrorPage.render(404, path: req.path)]]
        end

        def render_page_error(req, error_file, exception = nil)
          html = nil

          if error_file
            begin
              doc, parser = Core::Loader::PageLoader.load(error_file, {}, req.cookies, {})
              html = Core::Renderer::Renderer.render(doc, parser)
            rescue
              html = nil
            end
          end

          html ||= Aura::Error.handle(
            exception || ::RuntimeError.new("Page rendering failed"),
            env: Aura.env
          )

          [500, { "content-type" => "text/html; charset=utf-8" }, [html]]
        end

        def find_page_file(target)
          candidates = [
            File.expand_path("app/#{target}.rb", @project_root),
            File.expand_path("#{target}.rb", @project_root),
            File.expand_path("app/#{target}", @project_root),
            File.expand_path(target, @project_root)
          ]
          candidates.find { |p| File.file?(p) }
        end

        def cookie_header(session_id)
          secure = Aura.env == "production" ? "; Secure" : ""
          "aura_session_id=#{session_id}; Path=/; HttpOnly; SameSite=Lax#{secure}"
        end

        def sign_session_id(id, issued_at = Time.now.to_i)
          payload = "#{id}.#{issued_at}"
          "#{payload}.#{hmac(payload)}"
        end

        def read_session_token(token)
          return nil if token.nil? || token.empty?

          id, ts, sig = token.split(".")
          return nil if id.nil? || id.empty? || ts.nil? || sig.nil?
          return nil unless signature_valid?("#{id}.#{ts}", sig)
          return nil if @session_ttl.positive? && (Time.now.to_i - ts.to_i) > @session_ttl

          id
        end

        def signature_valid?(payload, signature)
          expected = hmac(payload)
          return false unless signature.is_a?(String) && signature.bytesize == expected.bytesize

          secure_compare(expected, signature)
        end

        def hmac(payload)
          ::OpenSSL::HMAC.hexdigest("SHA256", @session_secret, payload)
        end

        def rotate_session(session_id)
          data   = @session_store.read(session_id)
          new_id = @session_store.generate_id
          @session_store.write(new_id, data)
          new_id
        rescue StandardError
          session_id
        end

        def flash_keys(session_data)
          session_data.keys.select { |k| k.to_s.start_with?("flash:") }
        end

        def consume_flash!(session_data, keys)
          keys.each { |k| session_data.delete(k) }
          nil
        end

        def redirect_from(parser)
          return nil unless parser

          if parser.respond_to?(:redirect) && (found = parser.redirect)
            return found
          end

          compiler = parser.instance_variable_get(:@compiler)
          return nil unless compiler

          begin
            compiler.redirect
          rescue StandardError
            nil
          end
        end

        def redirect_response(path, session_id)
          [303, {
            "location"   => path.to_s,
            "set-cookie" => cookie_header(sign_session_id(session_id))
          }, []]
        end

        def parse_action_request(req)
          if req.json_request?
            json = req.json_body
            {
              handler: json[:handler] || json["handler"],
              csrf:    json[:csrf] || json["csrf"],
              value:   json.key?(:value) ? json[:value] : json["value"],
              form:    json[:form] || json["form"],
              field:   json[:field] || json["field"]
            }
          else
            form = req.form_params
            {
              handler: form["__handler"] || form[:__handler],
              csrf:    form["__csrf"] || form[:__csrf],
              value:   nil,
              form:    form_payload(form),
              field:   form["__field"] || form[:__field]
            }
          end
        end

        def form_payload(form)
          form.reject { |k, _| %w[__handler __csrf __field].include?(k.to_s) }
        end

        def page_cache_key(path)
          :"page:#{path}"
        end

        def read_page_cache_entry(key)
          return nil unless Core::Cache::Store.shared.key?(key)

          Core::Cache::Store.shared.fetch(key, ttl: nil) { nil }
        end

        def page_cache_fresh?(entry, ttl)
          return false unless entry

          (monotonic - entry[:stored_at].to_f) < ttl.to_f
        end

        def write_page_cache(key, html, ttl)
          Core::Cache::Store.shared.revalidate(key)
          Core::Cache::Store.shared.fetch(key, ttl: nil) do
            { html: html, stored_at: monotonic, ttl: ttl.to_f }
          end
          nil
        end

        def schedule_page_refresh(req, page_path, session_data, page_cache, cache_key)
          enqueue = @refresh_mutex.synchronize do
            next false if @refreshing[cache_key]

            @refreshing[cache_key] = true
          end
          return unless enqueue

          cookie = req.cookies
          snap   = session_data.dup

          Thread.new do
            begin
              doc, parser = Core::Loader::PageLoader.load(
                page_path, snap, cookie, {},
                layout_files: @router.layout_chain(page_path),
                loading_file: @router.loading_file_for(page_path)
              )
              html = Core::Renderer::Renderer.render(doc, parser)
              write_page_cache(cache_key, html, page_cache[:ttl])
            rescue StandardError
              nil
            ensure
              @refresh_mutex.synchronize { @refreshing.delete(cache_key) }
            end
          end
        end

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def trace_request(req, &block)
          return block.call unless @tracing

          @tracer.trace("aura.request", method: req.method, path: req.path, &block)
        end

        def handle_defer(req, session_data)
          name = (req.params["name"] || req.params[:name]).to_s
          return [400, { "content-type" => "text/plain" }, ["Bad Request: name required"]] if name.empty?

          page_ref  = req.params["page"] || req.params[:page]
          page_path = page_ref ? resolve_defer_page(page_ref) : session_data[:aura_current_page]
          unless page_path && File.file?(page_path)
            return [404, { "content-type" => "text/plain" }, ["Not Found: page not resolved"]]
          end

          catalog, loc = locale_catalog(req, session_data)
          doc, parser = Core::Loader::PageLoader.load(
            page_path, session_data, req.cookies, req.params,
            layout_files: @router.layout_chain(page_path),
            loading_file: @router.loading_file_for(page_path),
            i18n: catalog,
            locale: loc
          )

          if (entry = doc.handlers[:mount])
            mount_handler = entry.is_a?(Hash) ? entry[:handler] : entry
            mount_handler.call if mount_handler
          end

          resolved = parser.rebuild_ast!
          node = find_defer_node(resolved, name)
          return [404, { "content-type" => "text/plain" }, ["Not Found: defer fragment"]] unless node

          html = node.children.map { |child| Core::Renderer::HtmlRenderer.render(child) }.join
          [200, { "content-type" => "text/html; charset=utf-8" }, [html]]
        rescue => e
          body = Aura.env == "production" ? "Internal Server Error" : "Defer error: #{e.message}"
          [500, { "content-type" => "text/plain" }, [body]]
        end

        def resolve_defer_page(ref)
          if (match = @router.resolve(ref))
            route, = match
            find_page_file(route.target)
          elsif File.file?(ref)
            ref
          end
        end

        def find_defer_node(node, name)
          return node if node.is_a?(::Aura::Core::AST::ElementNode) &&
                         node.attrs["data-aura-defer"].to_s == name
          return nil unless node.respond_to?(:children) && node.children

          node.children.each do |child|
            found = find_defer_node(child, name)
            return found if found
          end
          nil
        end

        SENSITIVE_EXTENSIONS = %w[.bak .env .key .pem .rb .ru].freeze

        def static_file?(path)
          file_path = resolve_static_file_path(path)
          return false unless file_path
          return false unless File.file?(file_path)
          true
        end

        def serve_static_file(path)
          file_path = resolve_static_file_path(path)
          raise "Static file not found" unless file_path && File.file?(file_path)

          mime = Rack::Mime.mime_type(File.extname(file_path), "application/octet-stream")
          cache = Aura.env == "production" ? "public, max-age=3600" : "no-cache, no-store, must-revalidate"
          [200, { "content-type" => mime, "cache-control" => cache }, [File.binread(file_path)]]
        end

        def resolve_static_file_path(path)
          return nil if path.nil? || path.empty?

          decoded = ::URI::DEFAULT_PARSER.unescape(path)
          return nil unless decoded.valid_encoding?
          return nil if decoded.include?("\0") || decoded.include?("\\")

          cleaned = decoded.sub(/\A\/+/, "")
          segments = cleaned.split("/")
          return nil if segments.empty? || segments.any? { |segment| segment.start_with?(".") || segment == ".." }
          return nil if SENSITIVE_EXTENSIONS.include?(File.extname(cleaned).downcase)

          @static_paths.each do |static_path|
            next unless cleaned == static_path || cleaned.start_with?("#{static_path}/")

            static_root = File.realpath(File.join(@project_root, static_path))
            next unless path_within?(static_root, @project_root)
            next unless File.directory?(static_root)

            candidate = File.realpath(File.join(@project_root, cleaned))
            return candidate if path_within?(candidate, static_root)
          end
          nil
        rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP, ArgumentError, EncodingError
          nil
        end

        def normalize_static_paths(paths)
          Array(paths).map do |path|
            value = path.to_s
            segments = value.split("/")
            if value.empty? || value.start_with?("/") || value.include?("\\") ||
               segments.any? { |segment| segment.empty? || segment == "." || segment == ".." || segment.start_with?(".") }
              raise ArgumentError, "Invalid static asset path: #{path.inspect}"
            end
            value
          end.uniq.freeze
        end

        def path_within?(path, root)
          path == root || path.start_with?(root + File::SEPARATOR)
        end

        CLIENT_RUNTIME_PATH = File.expand_path("../client/aura-client.js", __dir__).freeze

        def serve_client_runtime
          body = File.read(CLIENT_RUNTIME_PATH)
          body = body.sub("    connectLiveReload();", "") if Aura.env == "production"
          cache = Aura.env == "production" ? "public, max-age=3600" : "no-cache"
          [200, {
            "content-type"  => "application/javascript; charset=utf-8",
            "cache-control" => cache
          }, [body]]
        end

        def handle_live_reload(_req)
          watcher = live_reload_watcher
          poll_interval = 0.3

          body = Enumerator.new do |yielder|
            yielder << "data: ping\n\n"
            loop do
              sleep poll_interval
              if watcher.changed?
                yielder << "data: reload\n\n"
                break
              end
              yielder << "data: ping\n\n"
            rescue
              break
            end
          end

          [200, {
            "content-type" => "text/event-stream",
            "cache-control" => "no-cache",
            "connection"    => "keep-alive"
          }, body]
        end

        def live_reload_watcher
          @live_reload_watcher ||= LiveReloadWatcher.start
        end

        def secure_compare(a, b)

          l = a.bytesize
          res = 0
          i = 0
          while i < l
            res |= a.getbyte(i) ^ b.getbyte(i)
            i += 1
          end
          res == 0
        end

        def render_error(res, req:, exception:, type_code:, message:)
          diagnostic = Aura::Error::Diagnostics::Diagnostic.new(
            type_code: type_code,
            title: "Error: #{type_code}",
            message: message,
            stack: exception ? exception.backtrace : caller
          )
          html = Aura::Error.renderer.render(diagnostic)
          res.status = 404 if type_code == :route_not_found
          res.write(html)
          res.finish
        end

      end
    end
  end
end
