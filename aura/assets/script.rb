module Aura
  module Assets
    class Script
      attr_reader :path

      def initialize(path)
        @path = path
      end

      def to_html
        "<script src=\"#{@path}\"></script>"
      end
    end
  end
end
