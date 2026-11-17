require_relative "../../security/capability_context"
require_relative "../ast/nodes"
require_relative "../parser/ripper_preprocessor"
require_relative "../parser/nodes/document"
require_relative "../parser/nodes/element"
require_relative "../parser/nodes/text"

module Aura
  module Core
    module DSL
      class ASTCompiler < ::BasicObject
        def initialize(capabilities = nil, document = nil, current_node = nil, props = {}, children_block = nil, session: {}, cookies: {}, params: {}, i18n: nil, locale: nil, context: nil, query: {}, fragment: nil, cookies_out: nil, loader_cache: nil)
          @capabilities = capabilities || ::Aura::Security::CapabilityContext.default
          @document = document || ::Aura::Core::Document.new
          @current_node = current_node || @document
          @components = {}
          @layouts = {}
          @props = props
          @children_block = children_block
          @session = session || {}
          @cookies = cookies || {}
          @params = params || {}
          @computed = {}
          @computed_cache = {}
          @effects = []
          @tracker = nil

          @loaders = {}
          @loader_cache = loader_cache || {}

          @errors = {}

          @i18n = i18n
          @locale = locale

          @context         = context || {}
          @in_component    = false
          @state_scope     = nil
          @named_slots     = {}
          @default_slots   = []
          @slots_ready     = false
          @slot_collector  = nil
          @component_error = nil
          @component_error_handler = nil

          @batch_depth         = 0
          @pending_invalidations = nil
          @cleanups            = {}
          @current_effect_id   = nil
          @optimistic          = {}
          @stores              = {}

          @cookies_out         = cookies_out || {}

          @styles     = []
          @memo_cache = {}
          @redirect   = nil
          @query      = query || {}
          @fragment   = fragment

          @suspense_seq = 0
        end

        attr_reader :document, :components, :layouts, :render_block, :computed, :effects, :loaders, :errors,
                    :context, :optimistic, :styles, :state_scope, :redirect,
                    :component_error_handler, :cookies_out

        attr_writer :state_scope, :in_component

        def title(val)
          @document.title = val
        end

        def lang(val)
          @document.lang = val
        end

        def meta(attrs = {})
          @document.meta_tags << attrs
        end

        def seo(&block)
          seo_helper = ::Aura::Core::DSL::SeoHelper.new
          seo_helper.instance_exec(&block) if block
          @document.seo = seo_helper.data
        end

        def asset(arg)
          type, path = arg
          resolved_path = ::File.expand_path(path, ::Dir.pwd)
          unless ::File.file?(resolved_path)
            ::Kernel.raise ::Aura::Error::AssetNotFoundError.new(
              asset_type: type,
              asset_path: path,
              checked_paths: [resolved_path]
            )
          end

          case type.to_sym
          when :css
            @document.assets.css << path
          when :script
            @document.assets.scripts << path
          when :prefetch
            @document.assets.prefetch << path
          when :favicon
            @document.assets.favicon = path
          end
        end

        def css(path)
          [:css, path]
        end

        def script(path)
          [:script, path]
        end

        def favicon(path)
          [:favicon, path]
        end

        def prefetch(path, as: nil)
          @document.assets.prefetch << [path, as]
          nil
        end

        def render(&block)
          @render_block = block if block
          instance_exec(&block) if block
          @document
        end

        def fragment(&block)
          node = ::Aura::Core::Element.new("fragment")
          @current_node.add(node)
          if block
            old = @current_node
            @current_node = node
            instance_exec(&block)
            @current_node = old
          end
          node
        end

        def text(val)
          @current_node.add(::Aura::Core::Text.new(val))
        end

        def raw(html)
          @current_node.add(::Aura::Core::AST::RawNode.new(html.to_s))
        end

        def slot(name = :content, content = nil, &block)
          if @slot_collector
            @slot_collector[name.to_sym] = block || content
            return nil
          end

          _ensure_slots!
          key = name.to_sym
          if key == :content || key == :default
            @default_slots.each { |n| @current_node.add(n) }
          else
            entry = @named_slots[key]
            if entry.nil?
              instance_exec(&block) if block
            else
              _render_slot_entry(entry)
            end
          end
          nil
        end

        def layout(name, &block)
          @layouts[name.to_sym] = block
          name.to_sym
        end

        def use(layout_ref)
          @document.layout = layout_ref
        end

        def include(path)
          resolved_path = ::Aura::Core::DSL::ASTCompiler.find_include_file(path)
          if resolved_path
            code = ::File.read(resolved_path, encoding: 'utf-8')
            processed = ::Aura::Core::RipperPreprocessor.process(code)
            dsl_proc = ::Aura::Security::ConstantSandbox.compile_source(processed, resolved_path, @capabilities)
            instance_exec(&dsl_proc)
          else
            ::Kernel.raise "Include file not found: #{path}"
          end
        end

        def define(name, fallback: nil, **defaults, &block)
          @components[name.to_sym] = { defaults: defaults, block: block, fallback: fallback }
        end

        def component(name, **props, &block)
          node = ::Aura::Core::AST::ComponentNode.new(name, props, block)
          @current_node.add(node)
          node
        end

        def compose(name, **preset)
          comp = self
          ->(**extra, &blk) { comp.component(name, **preset.merge(extra), &blk) }
        end

        def provide(key, value = nil, &block)
          @context[key.to_sym] = block || value
          nil
        end

        def inject(key, default = nil)
          value = @context[key.to_sym]
          return default if value.nil?
          return instance_exec(&value) if value.respond_to?(:call)

          value
        end

        def ref(name, tag = :div, **attrs, &block)
          attrs = attrs.merge("data-aura-ref" => name.to_s)
          _tag(tag.to_s, attrs, &block)
        end

        def portal(target = "body", &block)
          node = ::Aura::Core::Element.new("div", { "data-aura-portal" => target.to_s })
          @current_node.add(node)
          if block
            old = @current_node
            @current_node = node
            instance_exec(&block)
            @current_node = old
          end
          node
        end

        def suspense(name = nil, fallback: nil, &block)
          return nil unless block

          @suspense_seq += 1
          id = (name || @suspense_seq).to_s

          node = ::Aura::Core::Element.new("div", { "data-aura-suspense" => id })
          @current_node.add(node)

          old = @current_node
          @current_node = node
          begin
            _render_suspense_fallback(fallback)
          ensure
            @current_node = old
          end

          @document.suspense_blocks[id] = { block: block, fallback: fallback, node: node }
          node
        end

        def resolve_suspense(id)
          entry = @document.suspense_blocks[id.to_s]
          return nil unless entry

          node = entry[:node]
          node.children.clear

          old = @current_node
          @current_node = node
          begin
            instance_exec(&entry[:block])
          rescue ::StandardError
            node.children.clear
            _render_suspense_fallback(entry[:fallback])
          ensure
            @current_node = old
          end
          node
        end

        def defer(name, fallback: nil)
          node = ::Aura::Core::Element.new("span", { "data-aura-defer" => name.to_s })
          node.add(::Aura::Core::Text.new(fallback.to_s)) if fallback
          @current_node.add(node)
          node
        end

        def memo(key, ttl: nil, &block)
          return nil unless block

          nodes =
            if ttl
              ::Aura::Core::Cache::Store.shared.fetch(:"memo:#{key}", ttl: ttl) { _capture_nodes(block) }
            else
              @memo_cache[key.to_s] ||= _capture_nodes(block)
            end
          nodes.each { |n| @current_node.add(_deep_dup_node(n)) }
          nil
        end

        def on(event_name, public: false, revalidate: nil, &block)
          @document.handlers[event_name.to_sym] = {
            handler: block,
            public: !!public,
            revalidate: revalidate
          }
        end

        def public_on(event_name, revalidate: nil, &block)
          on(event_name, public: true, revalidate: revalidate, &block)
        end

        def on_error(&block)
          if @in_component
            @component_error_handler = block
          else
            @document.handlers[:error] = { handler: block, public: false }
          end
        end

        def on_unmount(&block)
          @document.handlers[:unmount] = { handler: block, public: false }
        end

        def loader(name, ttl: nil, tags: [], store: true, &block)
          tag_list = tags.is_a?(::Array) ? tags : [tags]
          @loaders[name.to_sym] = { block: block, ttl: ttl, tags: tag_list.map(&:to_sym), store: store }
          nil
        end

        def data(name, force: false)
          key = name.to_sym
          return @loader_cache[key] if !force && @loader_cache.key?(key)

          entry = @loaders[key]
          return nil unless entry

          value =
            if entry[:store] == false
              instance_exec(&entry[:block])
            elsif entry[:ttl]
              ::Aura::Core::Cache::Store.shared.fetch(:"loader:#{key}", ttl: entry[:ttl]) do
                instance_exec(&entry[:block])
              end
            else
              instance_exec(&entry[:block])
            end

          @loader_cache[key] = value
          value
        end

        def revalidate(*names)
          names = @loaders.keys if names.empty?
          keys = names.map { |n| :"loader:#{n}" }
          ::Aura::Core::Cache::Store.shared.revalidate(*keys)
          @loader_cache.clear
          nil
        end

        def revalidate_tag(*tags)
          wanted = tags.map(&:to_sym)
          keys = @loaders.select { |_, e| (e[:tags] & wanted).any? }.keys.map { |n| :"loader:#{n}" }
          ::Aura::Core::Cache::Store.shared.revalidate(*keys)
          @loader_cache.clear
          nil
        end

        def data_section(name, loading: nil, error: nil, &block)
          value = data(name)
          if value.nil? && loading
            return loading.respond_to?(:call) ? instance_exec(&loading) : text(loading.to_s)
          end
          block ? instance_exec(value, &block) : text(value.to_s)
        rescue ::StandardError => e
          raise unless error

          error.respond_to?(:call) ? instance_exec(e, &error) : text(error.to_s)
        end

        def page_cache(ttl, swr: false)
          @document.page_cache = { ttl: ttl.to_i, swr: !!swr }
          nil
        end

        def validate(input, rules = {})
          @errors = ::Aura::Core::Forms::Validator.validate(input, rules)
        end

        def errors
          @errors
        end

        def error_for(field)
          @errors[field.to_sym]
        end

        def t(key, **vars)
          return key.to_s unless @i18n.respond_to?(:t)

          if vars.key?(:count) && @i18n.respond_to?(:t_plural)
            @i18n.t_plural(key, vars[:count], **vars)
          else
            @i18n.t(key, **vars)
          end
        end

        def locale
          @locale || (@i18n.respond_to?(:locale) ? @i18n.locale : "en")
        end

        def format_date(time, format: :short)
          ::Aura::I18n::Formatting.date(time, locale, format: format)
        end

        def format_number(value, precision: nil)
          ::Aura::I18n::Formatting.number(value, locale, precision: precision)
        end

        def format_currency(value, code = "EUR")
          ::Aura::I18n::Formatting.currency(value, code, locale)
        end

        def param(name, type:, required: true)
          @document.param_types[name.to_sym] = { type: type.to_sym, required: required }
        end

        def query
          @query
        end

        def query_param(name, default = nil)
          @query[name.to_s] || @query[name.to_sym] || default
        end

        def url_fragment
          @fragment
        end

        def static_(&block)
          _mark_block(block, "data-aura-static" => "1")
        end

        def client_(&block)
          _mark_block(block, "data-aura-client" => "1")
        end

        def island(name, hydrate: true, &block)
          _mark_block(block, "data-aura-island" => name.to_s, "data-aura-hydrate" => (hydrate ? "1" : "0"))
        end

        def field(name, type: "text", label: nil, **attrs)
          div class: "field-group" do
            label name.to_s.capitalize if label
            input type: type, name: name, **attrs
          end
        end

        def submit(value, **attrs)
          input type: "submit", value: value, **attrs
        end

        def form_for(handler, method: "post", **attrs, &block)
          csrf = @session[:aura_csrf]
          form method: method, action: "/_aura/action", **attrs do
            input type: "hidden", name: "__handler", value: handler.to_s
            input type: "hidden", name: "__csrf", value: csrf.to_s if csrf
            instance_exec(&block) if block
          end
        end

        def redirect_to(path)
          @redirect = path.to_s
          nil
        end

        def flash(name, value = :__aura_get__)
          key = :"flash:#{name}"
          if value == :__aura_get__
            @session[key]
          else
            @session[key] = value
            nil
          end
        end

        def clear_flash(name = nil)
          if name
            @session.delete(:"flash:#{name}")
          else
            @session.keys.each { |k| @session.delete(k) if k.to_s.start_with?("flash:") }
          end
          nil
        end

        def step(name = "default", initial = 1)
          key = :"step:#{name}"
          @session[key] ||= initial
        end

        def next_step(name = "default")
          key = :"step:#{name}"
          @session[key] = (step(name) + 1)
        end

        def reset_step(name = "default")
          @session.delete(:"step:#{name}")
          nil
        end

        def uploaded_file(name)
          raw = @params[name.to_sym] || @params[name.to_s]
          return nil unless raw.is_a?(::Hash)

          temp = raw[:tempfile] || raw["tempfile"]
          {
            filename: raw[:filename] || raw["filename"],
            type: raw[:type] || raw["type"],
            tempfile: temp,
            size: temp.respond_to?(:size) ? temp.size : nil
          }
        end

        def not_found!
          ::Kernel.raise ::Aura::Core::NotFound
        end

        def define_store(name, initial = {})
          @stores[name.to_sym] = initial
          @session[:"shared:#{name}"] ||= initial.dup
          self
        end

        def shared_store(name)
          @session[:"shared:#{name}"]
        end

        def optimistic(name = nil, value = nil, &block)
          return @optimistic if name.nil?

          @optimistic[name.to_sym] = block || value
          nil
        end

        def optimistic_values
          @optimistic.each_with_object({}) do |(key, value), acc|
            acc[key] = value.is_a?(::Proc) ? value.call : value
          end
        end

        def cookie(name)
          @cookies[name.to_s]
        end

        def store(name, value = nil, scope: :session, ttl: nil, max_age: nil)
          return _store_read(name, scope) if value.nil?

          case scope.to_sym
          when :memory, :redis
            ::Aura::Core::Cache::Store.shared.fetch(:"store:#{scope}:#{name}", ttl: ttl) { value }
          when :cookie
            @cookies_out[name.to_s] = { value: value, max_age: max_age }
            value
          else
            @session[name.to_sym] = value
          end
        end

        def params
          @params
        end

        def session
          @session
        end

        def prop(name)
          value = @props[name.to_sym] || @props[name.to_s]
          text(value.to_s) unless value.nil?
        end

        def props
          @props
        end

        def prop_value(name)
          @props.key?(name.to_sym) ? @props[name.to_sym] : @props[name.to_s]
        end

        def yield_content
          slot(:content)
        end

        def state(name, initial = nil)
          ivar = :"@#{name}"
          unless _ivar_defined?(ivar)
            if @state_scope
              skey = :"#{@state_scope}#{name}"
              _ivar_set(ivar, @session.key?(skey) ? @session[skey] : initial)
            else
              _ivar_set(ivar, initial)
            end
          end
          _ivar_get(ivar)
        end

        def computed(name, &block)
          n = name.to_sym
          @computed[n] = block
          @computed_cache.delete(n)
        end

        def get(name)
          n = name.to_sym

          if @computed.key?(n)
            cached = @computed_cache[n]
            return cached[:value] if cached

            deps = []
            previous = @tracker
            @tracker = deps
            begin
              value = instance_exec(&@computed[n])
            ensure
              @tracker = previous
            end
            @computed_cache[n] = { value: value, deps: deps }
            deps.each { |d| @tracker << d } if @tracker
            return value
          end

          _track(n)
          ivar = :"@#{n}"
          _ivar_defined?(ivar) ? _ivar_get(ivar) : nil
        end

        def set(name, value)
          _ivar_set(:"@#{name}", value)
          @session[:"#{@state_scope}#{name}"] = value if @state_scope
          if @batch_depth.zero?
            _invalidate(name.to_sym)
          else
            (@pending_invalidations ||= []) << name.to_sym
          end
          value
        end

        def batch
          @batch_depth += 1
          yield
        ensure
          @batch_depth -= 1
          if @batch_depth.zero? && @pending_invalidations
            @pending_invalidations.uniq.each { |n| _invalidate(n) }
            @pending_invalidations = nil
          end
        end

        def state_snapshot
          snap = {}
          ::Kernel.instance_method(:instance_variables).bind(self).call.each do |var|
            name = var.to_s
            next unless name.start_with?("@")
            next if INTERNAL_IVARS.include?(name)
            val = _ivar_get(var)
            next if val.is_a?(::Proc) || val.is_a?(::Array) && name == "@effects"
            snap[name.sub("@", "").to_sym] = _deep_freeze(val)
          end
          snap
        end

        def state_diff(previous)
          snapshot = state_snapshot
          return snapshot unless previous.is_a?(::Hash)

          snapshot.each_with_object({}) do |(key, value), acc|
            acc[key] = value unless previous.key?(key) && previous[key] == value
          end
        end

        def effect(name = nil, &block)
          @effects << { name: name && name.to_sym, block: block }
          nil
        end

        def cleanup(&block)
          return nil unless block

          id = @current_effect_id
          (@cleanups[id] ||= []) << block
          nil
        end

        def run_effects!(deps_store = {})
          ran = false

          @effects.each_with_index do |eff, index|
            id   = eff[:name] || index
            deps = deps_store[id]
            dirty = deps.nil? || deps.any? { |dep, val| _current_value(dep) != val }
            next unless dirty

            (@cleanups[id] || []).each { |c| instance_exec(&c) }
            @cleanups[id] = []

            read = []
            previous = @tracker
            previous_id = @current_effect_id
            @tracker = read
            @current_effect_id = id
            begin
              instance_exec(&eff[:block])
            ensure
              @tracker = previous
              @current_effect_id = previous_id
            end

            snapshot = {}
            read.each { |dep| snapshot[dep] = _current_value(dep) }
            deps_store[id] = snapshot
            ran = true
          end

          ran
        end

        def show(condition, &block)
          return nil unless condition

          instance_exec(&block) if block
        end

        def unless_(condition, &block)
          return nil if condition

          instance_exec(&block) if block
        end

        def each(collection, key: nil, &block)
          return nil if collection.nil?

          collection.each_with_index do |item, index|
            before = @current_node.children.length
            instance_exec(item, index, &block)
            next unless key

            produced = @current_node.children[before..-1] || []
            root = produced.find { |n| n.is_a?(::Aura::Core::AST::ElementNode) }
            next unless root

            root.attrs = root.attrs.merge("data-aura-key" => _key_value(key, item, index).to_s)
          end
          nil
        end

        def bind(name, type: "text", options: nil, **attrs)
          n = name.to_s
          value = get(name)

          case type.to_s
          when "checkbox"
            input type: "checkbox", name: n, "data-bind": n, onchange: "__aura_bind",
                  checked: (value ? "checked" : nil), **attrs
          when "radio"
            input type: "radio", name: n, "data-bind": n, onchange: "__aura_bind", value: value, **attrs
          when "textarea"
            textarea name: n, "data-bind": n, oninput: "__aura_bind", **attrs do
              text(value.to_s)
            end
          when "select"
            select name: n, "data-bind": n, onchange: "__aura_bind", **attrs do
              (options || []).each do |opt|
                opt = [opt, opt] unless opt.is_a?(::Array)
                label_text, opt_value = opt
                selected = opt_value.to_s == value.to_s ? "selected" : nil
                option value: opt_value, selected: selected.to_s.empty? ? nil : "selected" do
                  text(label_text.to_s)
                end
              end
            end
          else
            input type: type, name: n, value: value, "data-bind": n, oninput: "__aura_bind", **attrs
          end
        end

        def aria(role: nil, label: nil, &block)
          attrs = {}
          attrs[:role] = role if role
          attrs["aria-label"] = label if label
          div(attrs, &block)
        end

        LANDMARKS = {
          main: "main", nav: "nav", header: "header", footer: "footer",
          aside: "aside", section: "section", article: "article",
          search: "form", region: "section", form: "form"
        }.freeze

        def landmark(role, **attrs, &block)
          tag = LANDMARKS[role.to_sym] || "div"
          _tag(tag, attrs.merge("role" => role.to_s), &block)
        end

        def main_(**attrs, &block)   = landmark(:main, **attrs, &block)
        def nav_(**attrs, &block)    = landmark(:nav, **attrs, &block)
        def header_(**attrs, &block) = landmark(:header, **attrs, &block)
        def footer_(**attrs, &block) = landmark(:footer, **attrs, &block)
        def aside_(**attrs, &block)  = landmark(:aside, **attrs, &block)

        def skip_link(target: "#main", label: "Skip to content")
          a href: target, class: "skip-link" do
            text(label)
          end
          nil
        end

        def p(*args, &block)      = _tag("p", *args, &block)
        def select(*args, &block) = _tag("select", *args, &block)
        def link(*args, &block)   = _tag("link", *args, &block)
        def open(*args, &block)   = _tag("div", *args, &block)

        ::Aura::Security::CapabilityContext.default_tags.each do |tag|
          next if %w[p select link open fragment data style].include?(tag)
          define_method(tag) do |*args, &block|
            _tag(tag, *args, &block)
          end
        end

        def style(css_text, class_name: nil)
          scope = @state_scope ? @state_scope.to_s.sub(/^ui_/, "").sub(/_+$/, "") : "aura"
          scoped, mapping = ::Aura::Assets::CssModules.scope(css_text.to_s, scope)
          @styles << scoped
          @document.styles << scoped
          klass = class_name ? mapping[class_name] : mapping.values.first
          klass || scope
        end

        def method_missing(name, *args, &block)
          name_sym = name.to_sym
          if @props.key?(name_sym)
            return @props[name_sym]
          end

          if @components.key?(name_sym)
            props = args.first.is_a?(::Hash) ? args.first : {}
            return component(name_sym, **props, &block)
          end

          capitalized = name.to_s.capitalize.to_sym
          if @components.key?(capitalized)
            props = args.first.is_a?(::Hash) ? args.first : {}
            return component(capitalized, **props, &block)
          end

          if args.empty? && block.nil?
            return nil
          end

          _tag(name.to_s, *args, &block)
        end

        def respond_to_missing?(name, include_private = false)
          name_sym = name.to_sym
          @props.key?(name_sym) ||
            @components.key?(name_sym) ||
            @components.key?(name.to_s.capitalize.to_sym) ||
            @capabilities.allowed_tag?(name)
        end

        def self.const_missing(name)
          ::Kernel.raise ::SecurityError, "Forbidden constant access in compiler: #{name}"
        end

        def const_missing(name)
          @capabilities.resolve_constant(name)
        end

        private

        INTERNAL_IVARS = %w[
          @capabilities @document @current_node @components @layouts @props
          @children_block @session @cookies @params @render_block @computed
          @computed_cache @effects @tracker @loaders @loader_cache @errors @i18n @locale
          @context @in_component @state_scope @named_slots @default_slots @slots_ready
          @slot_collector @component_error @component_error_handler @batch_depth
          @pending_invalidations @cleanups @current_effect_id @optimistic @stores
          @styles @memo_cache @redirect @query @fragment @suspense_seq
        ].freeze

        def _ivar_defined?(sym)
          ::Kernel.instance_method(:instance_variable_defined?).bind(self).call(sym)
        end

        def _ivar_get(sym)
          ::Kernel.instance_method(:instance_variable_get).bind(self).call(sym)
        end

        def _ivar_set(sym, val)
          ::Kernel.instance_method(:instance_variable_set).bind(self).call(sym, val)
        end

        def _track(name)
          @tracker << name if @tracker
        end

        def _current_value(name)
          ivar = :"@#{name}"
          _ivar_defined?(ivar) ? _ivar_get(ivar) : nil
        end

        def _invalidate(name)
          @computed_cache.delete_if { |_, entry| entry[:deps].include?(name) }
        end

        def _key_value(key, item, index)
          if key.respond_to?(:call)
            key.call(item, index)
          elsif item.is_a?(::Hash)
            item.key?(key.to_sym) ? item[key.to_sym] : (item.key?(key.to_s) ? item[key.to_s] : index)
          elsif item.respond_to?(key)
            item.public_send(key)
          else
            index
          end
        end

        def _render_suspense_fallback(fallback)
          return unless fallback

          fallback.respond_to?(:call) ? instance_exec(&fallback) : text(fallback.to_s)
        end

        def _capture_nodes(block)
          frag = ::Aura::Core::Element.new("fragment")
          old = @current_node
          @current_node = frag
          begin
            instance_exec(&block)
          ensure
            @current_node = old
          end
          frag.children
        end

        def _deep_dup_node(node)
          copy = node.dup
          copy.attrs = node.attrs.dup if node.respond_to?(:attrs) && node.attrs
          if node.respond_to?(:children) && node.children
            copy.children = node.children.map { |c| _deep_dup_node(c) }
          end
          copy
        end

        def _deep_freeze(value)
          case value
          when ::Hash
            value.each_with_object({}) { |(k, v), h| h[k] = _deep_freeze(v) }.freeze
          when ::Array
            value.map { |v| _deep_freeze(v) }.freeze
          else
            value
          end
        end

        def _ensure_slots!
          return if @slots_ready

          @slots_ready = true
          @named_slots = {}
          @default_slots = []
          return unless @children_block

          frag = ::Aura::Core::Element.new("fragment")
          old_node = @current_node
          old_collector = @slot_collector
          @current_node = frag
          @slot_collector = @named_slots
          begin
            instance_exec(&@children_block)
          ensure
            @current_node = old_node
            @slot_collector = old_collector
          end
          @default_slots = frag.children
        end

        def _render_slot_entry(entry)
          if entry.respond_to?(:call)
            frag = ::Aura::Core::Element.new("fragment")
            old = @current_node
            @current_node = frag
            begin
              instance_exec(&entry)
            ensure
              @current_node = old
            end
            frag.children.each { |n| @current_node.add(n) }
          else
            text(entry.to_s)
          end
        end

        def _mark_block(block, attrs)
          return nil unless block

          before = @current_node.children.length
          instance_exec(&block)
          produced = @current_node.children[before..-1] || []
          produced.each do |node|
            next unless node.respond_to?(:attrs) && node.attrs

            node.attrs = node.attrs.merge(attrs)
          end
          nil
        end

        def _store_read(name, scope)
          case scope.to_sym
          when :memory, :redis
            ::Aura::Core::Cache::Store.shared.fetch(:"store:#{scope}:#{name}", ttl: nil) { nil }
          when :cookie
            @cookies[name.to_s]
          else
            @session[name.to_sym]
          end
        end

        def _tag(tag_name, *args, **kwargs, &block)
          unless @capabilities.allowed_tag?(tag_name)
            ::Kernel.raise ::SecurityError, "Forbidden HTML tag: #{tag_name}"
          end

          attrs = kwargs.empty? ? (args.first.is_a?(::Hash) ? args.shift : {}) : kwargs
          text_content = args.first&.to_s

          node = ::Aura::Core::Element.new(tag_name, attrs)
          @current_node.add(node)

          if text_content
            node.add(::Aura::Core::Text.new(text_content))
          end

          if block
            old = @current_node
            @current_node = node
            instance_exec(&block)
            @current_node = old
          end
          node
        end

        def self.find_include_file(path)
          candidates = [
            ::File.expand_path("app/#{path}.rb"),
            ::File.expand_path("#{path}.rb"),
            ::File.expand_path("app/#{path}"),
            ::File.expand_path(path)
          ]
          candidates.find { |p| ::File.file?(p) }
        end
      end

      class SeoHelper
        attr_reader :data
        def initialize; @data = {}; end
        def title(v); @data[:title] = v; end
        def description(v); @data[:description] = v; end
        def og(h = {}); @data[:og] ||= {}; @data[:og].merge!(h); end
        def twitter(h = {}); @data[:twitter] ||= {}; @data[:twitter].merge!(h); end
        def canonical(v); @data[:canonical] = v; end
        def json_ld(h = {}); (@data[:json_ld] ||= []) << h; end
        def structured(h = {}); json_ld(h); end
        def keywords(v); @data[:keywords] = v; end
        def robots(v); @data[:robots] = v; end
      end
    end
  end
end
