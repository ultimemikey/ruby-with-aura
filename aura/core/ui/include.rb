module Aura
  module Core
    module UI

      class Include
        attr_reader :path

        def initialize(path)
          @path = path
        end
      end
    end
  end
end
