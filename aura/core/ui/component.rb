module Aura
  module Core
    module UI
      class Component
        attr_reader :name, :props, :block

        def initialize(name, props, block)
          @name  = name.to_sym
          @props = props
          @block = block
        end
      end
    end
  end
end
