require_relative "../../security/capability_context"
require_relative "compiler"
require_relative "../ast/nodes"

module Aura
  module Core
    module DSL
      class ExecutionContext
        attr_reader :capabilities, :session, :cookies, :params, :store_data, :components, :layouts, :context

        def initialize(capabilities:, session: {}, cookies: {}, params: {}, components: {}, layouts: {}, context: nil, cookies_out: nil)
          @capabilities = capabilities || ::Aura::Security::CapabilityContext.default
          @session = session || {}
          @cookies = cookies || {}
          @params = params || {}
          @store_data = {}
          @components = components || {}
          @layouts = layouts || {}

          @cookies_out = cookies_out || {}

          @context = context || {}

          @styles = []

          @component_seq = 0
        end

        def resolve(doc)

          resolved_doc = resolve_layouts(doc)

          resolved_doc.children = expand_children(resolved_doc.children)

          resolved_doc.styles = (resolved_doc.styles + @styles).uniq
          resolved_doc
        end

        def self.wrap!(layout_doc, inner_doc)
          layout_doc.title = inner_doc.title || layout_doc.title
          layout_doc.lang  = inner_doc.lang  || layout_doc.lang
          layout_doc.meta_tags      = layout_doc.meta_tags + inner_doc.meta_tags
          layout_doc.assets.css     = layout_doc.assets.css + inner_doc.assets.css
          layout_doc.assets.scripts = layout_doc.assets.scripts + inner_doc.assets.scripts
          layout_doc.assets.favicon = inner_doc.assets.favicon || layout_doc.assets.favicon
          layout_doc.seo            = inner_doc.seo.merge(layout_doc.seo)

          layout_doc.styles         = layout_doc.styles + inner_doc.styles

          layout_doc.handlers = layout_doc.handlers.merge(inner_doc.handlers)

          layout_doc.suspense_blocks = layout_doc.suspense_blocks.merge(inner_doc.suspense_blocks)

          place_into(layout_doc, inner_doc.children)
          layout_doc
        end

        def self.place_into(layout_doc, nodes)
          return if replace_slot(layout_doc, nodes)

          body_node = find_element(layout_doc, "body")
          if body_node
            nodes.each { |c| body_node.add(c) }
          else
            nodes.each { |c| layout_doc.add(c) }
          end
        end

        def self.replace_slot(node, replacement_nodes)
          return false unless node.respond_to?(:children) && node.children

          node.children.each_with_index do |child, index|
            if child.is_a?(::Aura::Core::AST::SlotNode)
              node.children.delete_at(index)
              node.children.insert(index, *replacement_nodes)
              replacement_nodes.each { |rn| rn.parent = node if rn.respond_to?(:parent=) }
              return true
            elsif child.respond_to?(:children) && child.children && !child.children.empty?
              return true if replace_slot(child, replacement_nodes)
            end
          end
          false
        end

        def self.find_element(node, tag)
          return node if node.is_a?(::Aura::Core::AST::ElementNode) && node.tag == tag
          if node.respond_to?(:children) && node.children
            node.children.each do |child|
              found = find_element(child, tag)
              return found if found
            end
          end
          nil
        end

        private

        def resolve_layouts(doc)
          return doc unless doc.layout

          layout_block = @layouts[doc.layout.to_sym]
          ::Kernel.raise "Layout not defined: #{doc.layout}" unless layout_block

          layout_compiler = ::Aura::Core::DSL::ASTCompiler.new(
            @capabilities,
            session: @session,
            cookies: @cookies,
            params:  @params,
            context: @context,
            cookies_out: @cookies_out
          )
          layout_compiler.components.merge!(@components)
          layout_compiler.layouts.merge!(@layouts)

          layout_doc = layout_compiler.render(&layout_block)

          self.class.wrap!(layout_doc, doc)
        end

        def expand_children(nodes)
          expanded = []
          nodes.each do |node|
            if node.is_a?(::Aura::Core::AST::ComponentNode)
              expanded.concat(expand_component(node))
            else
              if node.respond_to?(:children) && node.children
                node.children = expand_children(node.children)
              end
              expanded << node
            end
          end
          expanded
        end

        def expand_component(comp_node)
          comp_def = @components[comp_node.name]

          unless comp_def
            alternative_name = comp_node.name.to_s.downcase.to_sym
            comp_def = @components[alternative_name]
          end

          ::Kernel.raise "Component not defined: #{comp_node.name}" unless comp_def

          merged_props = comp_def[:defaults].merge(comp_node.props)

          comp_compiler = ::Aura::Core::DSL::ASTCompiler.new(
            @capabilities,
            nil,
            nil,
            merged_props,
            comp_node.block,
            session: @session,
            cookies: @cookies,
            params:  @params,
            context: @context,
            cookies_out: @cookies_out
          )
          comp_compiler.components.merge!(@components)
          comp_compiler.layouts.merge!(@layouts)

          @component_seq += 1
          comp_compiler.state_scope = :"ui_#{comp_node.name}_#{@component_seq}_"

          comp_compiler.in_component = true

          begin
            comp_doc = comp_compiler.render(&comp_def[:block])
          rescue ::StandardError => e

            fallback = comp_def[:fallback] || comp_compiler.component_error_handler
            ::Kernel.raise unless fallback

            @styles.concat(comp_compiler.styles)
            return render_fallback(fallback, e)
          end

          @styles.concat(comp_doc.styles)
          expand_children(comp_doc.children)
        end

        def render_fallback(fallback, error)
          return [::Aura::Core::AST::TextNode.new(fallback.to_s)] unless fallback.respond_to?(:call)

          fb = ::Aura::Core::DSL::ASTCompiler.new(
            @capabilities, nil, nil, {}, nil,
            session: @session, cookies: @cookies, params: @params, context: @context,
            cookies_out: @cookies_out
          )
          fb.components.merge!(@components)
          fb.layouts.merge!(@layouts)

          if fallback.arity == 1
            fb.render { instance_exec(error, &fallback) }
          else
            fb.render(&fallback)
          end
          fb.document.children
        end
      end
    end
  end
end
