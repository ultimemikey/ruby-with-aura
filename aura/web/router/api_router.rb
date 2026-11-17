require_relative "file_router"

module Aura
  module Web
    module Router

      class ApiRouter
        attr_reader :file_router

        def initialize(root = "app/api")
          @file_router = FileRouter.new(root)
        end

        def resolve(path)
          @file_router.resolve(path)
        end
      end
    end
  end
end
