module Aura
  module Error
    module Config
      class AuraErrorConfig
        DEFAULTS = {
          env: (ENV["RACK_ENV"] || ENV["APP_ENV"] || "development"),
          dev_overlay: true,
          stacktrace: true,
          suggestions: true,
          logger_enabled: true
        }.freeze

        attr_reader :env

        def initialize(overrides = {})
          @settings = DEFAULTS.merge(symbolize_keys(overrides))
          @env = @settings[:env].to_s
        end

        def dev?
          %w[development dev].include?(@env)
        end

        def prod?
          !dev?
        end

        def dev_overlay?
          !!@settings[:dev_overlay]
        end

        def show_stacktrace?
          !!@settings[:stacktrace]
        end

        def show_suggestions?
          !!@settings[:suggestions]
        end

        def logger_enabled?
          !!@settings[:logger_enabled]
        end

        private

        def symbolize_keys(hash)
          hash.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
        end
      end
    end
  end
end

