module Aura
  module Error
    module Diagnostics
      class Diagnostic
        attr_reader :type_code, :title, :message, :file, :line, :column, :stack, :suggestions, :context,
                    :causes, :exception_class

        def initialize(type_code:, title:, message:, file: nil, line: nil, column: nil, stack: [], suggestions: [], context: {}, causes: [], exception_class: nil)
          @type_code = type_code
          @title = title
          @message = message
          @file = file
          @line = line
          @column = column
          @stack = stack || []
          @suggestions = suggestions || []
          @context = context || {}
          @causes = causes || []
          @exception_class = exception_class
        end

        def location
          return nil unless file
          suffix = line ? ":#{line}" : ""
          suffix += ":#{column}" if column
          "#{file}#{suffix}"
        end

        def badge_label
          case type_code
          when :syntax_error
            "Build Error"
          when :route_not_found, :component_not_found, :file_not_found, :import_error, :server_error, :security_error, :state_error, :config_error, :hydration_error, :layout_not_found
            "Runtime Error"
          else
            title.to_s.include?("Build") ? "Build Error" : "Runtime Error"
          end
        end

        def root_cause
          causes.last || self
        end
      end
    end
  end
end

