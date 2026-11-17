module Aura
  module Core
    module UI
      class Layout
        attr_reader :name, :block

        def initialize(name, block)
          @name = name.to_sym
          @block = block
        end
      end
    end
  end
end
