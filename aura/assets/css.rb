module Aura
  module Assets
    class Css
      attr_reader :path

      def initialize(path)
        @path = path
      end

      def to_html
        "<link rel=\"stylesheet\" href=\"#{@path}\">"
      end
    end
  end
end
