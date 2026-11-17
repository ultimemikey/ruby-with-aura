require "securerandom"

module Aura
  module Error
    module Logger
      class AuraLogger
        attr_reader :logs

        def initialize
          @logs = []
        end

        def log(diagnostic, exception: nil)
          return unless diagnostic

          entry = {
            id: SecureRandom.uuid,
            timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),

            type_code: diagnostic.type_code,
            title: diagnostic.title,
            message: diagnostic.message,
            file: diagnostic.file,
            line: diagnostic.line,
            column: diagnostic.column,
            suggestions: diagnostic.suggestions,
            context: diagnostic.context,
            stack: (exception&.backtrace || diagnostic.stack)
          }

          @logs << entry
          entry
        end

        def to_json
          require "json"
          @logs.to_json
        end

        def export_json(path)
          require "json"
          File.write(path, JSON.pretty_generate(@logs))
        end
      end

      class Store
        def self.instance
          @instance ||= AuraLogger.new
        end

        def self.log(diagnostic, exception: nil)
          instance.log(diagnostic, exception: exception)
        end

        def self.logs
          instance.logs
        end
      end
    end
  end
end

