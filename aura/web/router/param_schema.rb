module Aura
  module Web
    module Router

      class ParamSchema
        STRING  = /\A.+\z/m
        INTEGER = /\A-?\d+\z/
        UUID    = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
        SLUG    = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/i

        TYPES = { string: STRING, integer: INTEGER, uuid: UUID, slug: SLUG }.freeze

        attr_reader :params

        def self.build(&block)
          schema = new
          schema.instance_eval(&block) if block
          schema
        end

        def initialize
          @params = {}
        end

        def param(name, type: :string, required: true)
          @params[name.to_sym] = { type: type.to_sym, required: required }
        end

        def empty?
          @params.empty?
        end

        def valid?(values)
          @params.all? do |name, spec|
            value = values.key?(name) ? values[name] : values[name.to_s]

            if value.nil?
              !spec[:required]
            else
              match_type?(value, spec[:type])
            end
          end
        end

        private

        def match_type?(value, type)
          pattern = TYPES[type]
          return true unless pattern

          pattern.match?(value.to_s)
        end
      end
    end
  end
end
