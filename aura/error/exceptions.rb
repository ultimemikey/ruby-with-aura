module Aura
  module Error
    class FrameworkError < StandardError
      attr_reader :details

      def initialize(message, details: {})
        @details = details
        super(message)
      end
    end

    class PageNotFoundError < FrameworkError
      def initialize(request_path:, target:, checked_paths: [])
        super(
          "No page file found for route target #{target.inspect}",
          details: {
            request_path: request_path,
            target: target,
            checked_paths: checked_paths
          }
        )
      end
    end

    class IncludeNotFoundError < FrameworkError
      def initialize(include_path:, checked_paths: [])
        super(
          "Include file not found: #{include_path}",
          details: {
            include_path: include_path,
            checked_paths: checked_paths
          }
        )
      end
    end

    class AssetNotFoundError < FrameworkError
      def initialize(asset_type:, asset_path:, checked_paths: [])
        super(
          "#{asset_type.to_s.capitalize} asset not found: #{asset_path}",
          details: {
            asset_type: asset_type,
            asset_path: asset_path,
            checked_paths: checked_paths
          }
        )
      end
    end

    class ComponentNotFoundError < FrameworkError
      def initialize(component_name:, available_components:, suggestions: [])
        super(
          "Component not defined: #{component_name}",
          details: {
            component_name: component_name,
            available_components: available_components,
            suggestions: suggestions
          }
        )
      end
    end

    class LayoutNotFoundError < FrameworkError
      def initialize(layout_name:, available_layouts:, suggestions: [])
        super(
          "Layout not defined: #{layout_name}",
          details: {
            layout_name: layout_name,
            available_layouts: available_layouts,
            suggestions: suggestions
          }
        )
      end
    end

    class InvalidEventHandlerError < FrameworkError
      def initialize(handler_name:)
        super(
          "Invalid event handler name: #{handler_name.inspect}",
          details: {
            handler_name: handler_name
          }
        )
      end
    end
  end
end
