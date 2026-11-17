module Aura
  module Core
    module AST
      class Node
        attr_accessor :children, :parent

        def initialize
          @children = []
          @parent   = nil
        end

        def add(node)
          ::Kernel.raise ::FrozenError, "can't modify frozen AST node" if frozen?
          node.parent = self if node.respond_to?(:parent=)
          @children << node
          node
        end

        def leaf?
          @children.empty?
        end

        def freeze
          @children.each(&:freeze)
          @children.freeze
          super
        end
      end

      class DocumentNode < Node
        attr_accessor :title, :lang, :meta_tags, :assets,
                      :handlers, :state, :layout, :seo,
                      :page_cache, :param_types, :suspense_blocks, :styles

        def initialize
          super()
          @title     = nil
          @lang      = "en"
          @meta_tags = []
          @assets    = AssetList.new
          @handlers  = {}
          @state     = {}
          @layout    = nil
          @seo       = {}
          @page_cache  = nil
          @param_types = {}

          @styles      = []

          @suspense_blocks = {}
        end

        def freeze
          @title.freeze
          @lang.freeze
          @meta_tags.each(&:freeze)
          @meta_tags.freeze
          @assets.freeze
          @handlers.each { |k, v| k.freeze; v.freeze }
          @handlers.freeze
          @state.each { |k, v| k.freeze; v.freeze }
          @state.freeze
          @layout.freeze
          @seo.each { |k, v| k.freeze; v.freeze }
          @seo.freeze
          @page_cache.freeze
          @param_types.each { |k, v| k.freeze; v.freeze }
          @param_types.freeze
          @styles.each(&:freeze)
          @styles.freeze
          super
        end

        AssetList = ::Struct.new(:css, :scripts, :favicon, :prefetch, keyword_init: true) do
          def initialize(css: [], scripts: [], favicon: nil, prefetch: [])
            super
          end

          def freeze
            css.each(&:freeze)
            css.freeze
            scripts.each(&:freeze)
            scripts.freeze
            favicon.freeze
            prefetch.each(&:freeze)
            prefetch.freeze
            super
          end
        end
      end

      class ElementNode < Node

        VOID_TAGS = %w[area base br col embed hr img input link meta param source track wbr].freeze

        attr_accessor :tag, :attrs

        def initialize(tag, attrs = {})
          super()
          @tag   = tag.to_s.downcase
          @attrs = attrs
        end

        def self_closing?
          VOID_TAGS.include?(@tag)
        end

        def freeze
          @tag.freeze
          @attrs.each { |k, v| k.freeze; v.freeze }
          @attrs.freeze
          super
        end
      end

      class TextNode < Node
        attr_accessor :value

        def initialize(value)
          super()
          @value = value.to_s
        end

        def leaf?
          true
        end

        def freeze
          @value.freeze
          super
        end
      end

      class RawNode < Node
        attr_accessor :html

        def initialize(html)
          super()
          @html = html.to_s
        end

        def leaf?
          true
        end

        def freeze
          @html.freeze
          super
        end
      end

      class SlotNode < Node
        attr_reader :name

        def initialize(name = :content)
          super()
          @name = name.to_sym
        end

        def freeze
          @name.freeze
          super
        end
      end

      class ComponentNode < Node
        attr_reader :name, :props, :block

        def initialize(name, props = {}, block = nil)
          super()
          @name  = name.to_sym
          @props = props
          @block = block
        end

        def freeze
          @name.freeze
          @props.each { |k, v| k.freeze; v.freeze }
          @props.freeze
          super
        end
      end
    end
  end
end
