require_relative "../../security/capability_context"
require_relative "nodes"

module Aura
  module Core
    module AST
      class Validator
        MAX_DEPTH = 100

        def self.validate!(node, capabilities = nil, depth = 0)
          capabilities ||= ::Aura::Security::CapabilityContext.default

          if depth > MAX_DEPTH
            ::Kernel.raise ::SecurityError, "[Aura Validator] Nesting depth limit exceeded (#{MAX_DEPTH})"
          end

          case node
          when DocumentNode
            node.children.each { |child| validate!(child, capabilities, depth + 1) }
          when ElementNode
            unless capabilities.allowed_tag?(node.tag)
              ::Kernel.raise ::SecurityError, "[Aura Validator] Forbidden HTML tag: `#{node.tag}`"
            end

            node.attrs.each do |k, v|
              key = k.to_s
              if key.start_with?("on")
                unless v.to_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
                  ::Kernel.raise ::SecurityError, "[Aura Validator] Invalid event handler name: #{v.inspect}"
                end
              elsif (key == "href" || key == "src") && v.to_s.gsub(/\s+/, "").downcase.start_with?("javascript:")
                ::Kernel.raise ::SecurityError, "[Aura Validator] Forbidden javascript: URI in attribute `#{key}`"
              end
            end

            node.children.each { |child| validate!(child, capabilities, depth + 1) }
          when TextNode

          when RawNode

          when SlotNode

          when ComponentNode
            unless node.name.to_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
              ::Kernel.raise ::SecurityError, "[Aura Validator] Invalid component name: #{node.name}"
            end
            node.children.each { |child| validate!(child, capabilities, depth + 1) }
          else
            ::Kernel.raise ::SecurityError, "[Aura Validator] Unknown AST node type: #{node.class}"
          end

          true
        end
      end
    end
  end
end
