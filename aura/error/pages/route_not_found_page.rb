require_relative "generic_error_page"

module Aura
  module Error
    module Pages
      class RouteNotFoundPage
        def self.render(diagnostic:, inner:)
          GenericErrorPage.render(diagnostic: diagnostic, inner: inner)
        end
      end
    end
  end
end

