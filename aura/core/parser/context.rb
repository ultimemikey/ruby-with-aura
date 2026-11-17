module Aura
  module Core
    class Context
      attr_accessor :current_node, :document

      def initialize
        @document = Document.new
        @current_node = @document
      end
    end
  end
end