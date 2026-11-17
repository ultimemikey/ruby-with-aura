require_relative "nodes/node"
require_relative "nodes/document"
require_relative "nodes/element"
require_relative "nodes/text"
require_relative "../ui/component"
require_relative "../ui/include"
require_relative "../ui/layout"
require_relative "../ui/slot"
require_relative "ripper_preprocessor"
require_relative "../../security/capability_context"
require_relative "../../security/constant_sandbox"
require_relative "../../core/dsl/compiler"
require_relative "../../core/dsl/execution_context"
require_relative "../../core/ast/validator"

module Aura
  module Core

    class Parser
      attr_reader :doc, :components, :layouts, :session, :cookies, :store_data, :params,
                  :query, :fragment

      def initialize(session = {}, cookies = {}, params = {}, layout_files: [], loading_file: nil, i18n: nil, locale: nil, query: {}, fragment: nil)
        @session    = session
        @cookies    = cookies
        @store_data = {}
        @params     = {}
        params.each { |k, v| @params[k.to_sym] = v } if params.is_a?(::Hash)

        @query    = query || {}
        @fragment = fragment

        @layout_files = layout_files || []
        @loading_file = loading_file

        @i18n   = i18n
        @locale = locale

        @capabilities = Security::CapabilityContext.default

        @cookies_out = {}

        @loader_cache = {}

        @compiler = DSL::ASTCompiler.new(
          @capabilities,
          session: @session,
          cookies: @cookies,
          params:  @params,
          i18n:    @i18n,
          locale:  @locale,
          query:   @query,
          fragment: @fragment,
          cookies_out: @cookies_out,
          loader_cache: @loader_cache
        )

        @doc        = @compiler.document
        @components = @compiler.components
        @layouts    = @compiler.layouts
        @render_block = nil
        @dsl_proc   = nil
      end

      def parse(file)
        code = File.read(file, encoding: "utf-8")
        parse_code(code, file)
      end

      def parse_code(code, filename = "(eval)")
        processed = RipperPreprocessor.process(code)

        dsl_proc = Security::ConstantSandbox.compile_source(processed, filename, @capabilities)
        @dsl_proc = dsl_proc
        @compiler.instance_exec(&dsl_proc)

        @doc        = @compiler.document
        @components = @compiler.components
        @layouts    = @compiler.layouts
        @render_block = @compiler.render_block

        exec_ctx = DSL::ExecutionContext.new(
          capabilities: @capabilities,
          session:      @session,
          cookies:      @cookies,
          params:       @params,
          components:   @components,
          layouts:      @layouts,
          context:      @compiler.context,
          cookies_out:  @cookies_out
        )
        @doc = exec_ctx.resolve(@doc)

        @doc = apply_route_conventions(@doc)

        AST::Validator.validate!(@doc, @capabilities)

        @doc
      end

      MAX_REACTIVE_PASSES = 10

      def rebuild_ast!
        state  = extract_state
        passes = 0

        effect_deps = {}

        while true

          @compiler = DSL::ASTCompiler.new(
            @capabilities,
            session: @session,
            cookies: @cookies,
            params:  @params,
            i18n:    @i18n,
            locale:  @locale,
            query:   @query,
            fragment: @fragment,
            cookies_out: @cookies_out,
            loader_cache: @loader_cache
          )

          inject_state(state)

          @compiler.instance_exec(&@dsl_proc) if @dsl_proc

          @doc          = @compiler.document
          @components   = @compiler.components
          @layouts      = @compiler.layouts
          @render_block = @compiler.render_block

          break unless @compiler.run_effects!(effect_deps)
          break if (passes += 1) >= MAX_REACTIVE_PASSES

          state = extract_state
        end

        exec_ctx = DSL::ExecutionContext.new(
          capabilities: @capabilities,
          session:      @session,
          cookies:      @cookies,
          params:       @params,
          components:   @components,
          layouts:      @layouts,
          context:      @compiler.context,
          cookies_out:  @cookies_out
        )
        @doc = exec_ctx.resolve(@doc)

        @doc = apply_route_conventions(@doc)

        AST::Validator.validate!(@doc, @capabilities)

        @doc
      end

      def extract_state
        state = {}
        compiler = @compiler

        vars = ::Kernel.instance_method(:instance_variables).bind(compiler).call
        vars.each do |var|

          next if %i[
            @capabilities @document @current_node @components @layouts @props
            @children_block @session @cookies @params @render_block @computed
            @computed_cache @effects @tracker
            @loaders @loader_cache @errors @i18n @locale @suspense_seq
            @cookies_out
          ].include?(var)
          val = ::Kernel.instance_method(:instance_variable_get).bind(compiler).call(var)
          state[var.to_s.sub("@", "").to_sym] = val
        end
        state
      end

      def inject_state(state_hash)
        return unless state_hash.is_a?(Hash)
        compiler = @compiler
        state_hash.each do |k, v|
          ::Kernel.instance_method(:instance_variable_set).bind(compiler).call("@#{k}", v)
        end
      end

      def optimistic
        @compiler.optimistic_values
      end

      def state_snapshot
        @compiler.state_snapshot
      end

      def state_diff(previous)
        @compiler.state_diff(previous)
      end

      def cookies_out
        @cookies_out
      end

      def clear_loader_cache!
        @loader_cache.clear
        nil
      end

      def current
        @compiler.instance_variable_get(:@current_node)
      end

      private

      def apply_route_conventions(doc)
        doc = apply_file_layouts(doc)
        doc = apply_loading_ui(doc)
        doc
      end

      def apply_file_layouts(doc)
        return doc if @layout_files.nil? || @layout_files.empty?

        @layout_files.reverse_each do |layout_file|
          layout_doc = build_isolated_doc(layout_file)
          doc = DSL::ExecutionContext.wrap!(layout_doc, doc)
        end
        doc
      end

      def apply_loading_ui(doc)
        return doc if @loading_file.nil?

        loading_doc = build_isolated_doc(@loading_file)
        wrapper = ::Aura::Core::Element.new(
          "div",
          { "data-aura-loading" => "1", "hidden" => "hidden" }
        )
        loading_doc.children.dup.each { |child| wrapper.add(child) }

        target = DSL::ExecutionContext.find_element(doc, "body") || doc
        target.add(wrapper)
        doc
      end

      def build_isolated_doc(file)
        self.class.new(
          @session, @cookies, @params,
          i18n: @i18n, locale: @locale,
          query: @query, fragment: @fragment
        ).parse(file)
      end
    end

    SeoContext = DSL::SeoHelper
  end
end