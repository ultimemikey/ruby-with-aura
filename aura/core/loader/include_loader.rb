module Aura
  module Core
    module Loader
      class IncludeLoader
        def self.load(path, parser)
          parser.include(path)
        end
      end
    end
  end
end
