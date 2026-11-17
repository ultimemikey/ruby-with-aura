module Aura
  module Assets
    class Favicon
      attr_reader :path

      def initialize(path)
        @path = path
      end

      def to_html
        "<link rel=\"icon\" type=\"image/png\" href=\"#{@path}\">"
      end
    end
  end
end
