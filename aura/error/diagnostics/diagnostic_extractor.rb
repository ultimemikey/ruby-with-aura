require "json"

module Aura
  module Error
    module Diagnostics
      class DiagnosticExtractor
        STACK_FRAME_RE = /^(?<file>.+):(?<line>\d+)(?::in [`'](?<method>[^']+)['`])?$/
        STACK_FRAME_RE_ALT = /^(?<file>.+):(?<line>\d+)(?::(?<column>\d+))?(?::\s*(?<rest>.*))?$/

        def self.extract(exception, type_code:, context: {})
          build_diagnostic(exception, type_code: type_code, context: context, collect_causes: true)
        end

        def self.build_diagnostic(exception, type_code:, context: {}, collect_causes: false)
          message = exception.respond_to?(:message) ? exception.message.to_s : exception.to_s
          stack = Array(exception.respond_to?(:backtrace) ? exception.backtrace : [])
          frame = stack.map { |l| parse_frame(l) }.compact.first || {}

          file = frame[:file]
          line = frame[:line]
          column = frame[:column]
          title = title_for(type_code)
          suggestions = suggestions_for(type_code, exception)
          causes = []

          if collect_causes && exception.respond_to?(:cause) && exception.cause
            seen = {}
            current = exception.cause
            while current && !seen[current.object_id]
              seen[current.object_id] = true
              ctype = begin
                ::Aura::Error.respond_to?(:map_exception_to_type_code) ? ::Aura::Error.map_exception_to_type_code(current) : :server_error
              rescue
                :server_error
              end
              causes << build_diagnostic(current, type_code: ctype, context: context, collect_causes: false)
              current = current.respond_to?(:cause) ? current.cause : nil
            end
          end

          Diagnostics::Diagnostic.new(
            type_code: type_code,
            title: title,
            message: message,
            file: file,
            line: line,
            column: column,
            stack: stack,
            suggestions: suggestions,
            context: context,
            causes: causes,
            exception_class: exception.class.name
          )
        end

        def self.parse_frame(line)
          str = line.to_s
          if (m = STACK_FRAME_RE.match(str))
            return { file: m[:file], line: m[:line].to_i, method: m[:method], raw: str }
          end
          if (m = STACK_FRAME_RE_ALT.match(str))
            return {
              file: m[:file],
              line: m[:line].to_i,
              column: (m[:column] && m[:column].to_i),
              method: m[:rest],
              raw: str
            }
          end
          { file: nil, line: nil, method: str, raw: str }
        end

        def self.title_for(type_code)
          {
            route_not_found: "Route Not Found",
            component_not_found: "Component Not Found",
            layout_not_found: "Layout Not Found",
            file_not_found: "File Not Found",
            import_error: "Import / Include Error",
            syntax_error: "Syntax Error",
            server_error: "Server Error",
            security_error: "Security Violation",
            state_error: "State Error",
            config_error: "Configuration Error",
            hydration_error: "Hydration Error"
          }[type_code] || "Aura Error"
        end

        def self.suggestions_for(type_code, exception)
          base = []
          case type_code
          when :route_not_found
            base << "Check the URL path and ensure a matching route exists in the router."
          when :component_not_found
            base << "Verify the component name is defined and registered before use."
          when :file_not_found
            base << "Ensure the page/include file exists and the target path is correct."
          when :import_error
            base << "Validate include/import paths and confirm the file is loadable from the expected directories."
          when :syntax_error
            base << "Inspect the syntax near the reported line/column. Ensure the Aura DSL transformations still produce valid Ruby."
          when :security_error
            base << "The DSL pipeline blocked access to a restricted constant or unapproved HTML tag. Verify capability configurations."
          when :server_error
            base << "Review the stack trace to find the failing call. If it occurs in a handler, verify handler parameters and state."
          when :state_error
            base << "Check reactive state extraction/injection. Ensure state shape matches what the UI expects."
          when :config_error
            base << "Check Aura configuration toggles (dev/prod, stacktrace, suggestions)."
          when :hydration_error
            base << "Verify client-server state alignment (actions + state injection)."
          else
            base << "Review the stack trace and confirm the failing code path."
          end
          if exception.is_a?(NameError)
            base << "A constant or method was not found. Confirm spelling/casing and ensure required files are loaded."
          end
          base.uniq
        end
      end
    end
  end
end

