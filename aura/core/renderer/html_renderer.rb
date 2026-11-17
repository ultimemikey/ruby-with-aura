require_relative "attribute_renderer"
require_relative "../ui/slot"
require_relative "../ast/nodes"

module Aura
  module Core
    module Renderer
      class HtmlRenderer
        def self.render(node)
          case node
          when AST::ElementNode
            if node.tag == "fragment"
              render_children(node)
            elsif node.self_closing?
              "<#{node.tag}#{AttributeRenderer.render(node.attrs)}>"
            else
              attrs = AttributeRenderer.render(node.attrs)
              "<#{node.tag}#{attrs}>#{render_children(node)}</#{node.tag}>"
            end
          when AST::TextNode
            AttributeRenderer.escape_html(node.value)
          when AST::RawNode

            node.html
          when UI::Slot, AST::SlotNode

            ""
          when AST::DocumentNode
            render_children(node)
          else
            ""
          end
        end

        def self.render_children(node)
          return "" unless node.respond_to?(:children) && node.children
          node.children.map { |child| render(child) }.join
        end
      end
    end
  end
end
