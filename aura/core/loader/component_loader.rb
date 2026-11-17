module Aura
  module Core
    module Loader
      class ComponentLoader
        def self.load(name, props, parser, &block)
          parser.component(name, **props, &block)
        end
      end
    end
  end
end
