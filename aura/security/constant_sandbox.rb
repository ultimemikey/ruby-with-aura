require "ripper"
require "set"

module Aura
  module Security

    module ConstantSandbox
      FORBIDDEN_METHODS = %w[
        __send__ send public_send instance_eval instance_exec eval class_eval
        module_eval method singleton_class define_method define_singleton_method
        remove_method const_get const_set autoload require load binding
        system exec spawn fork popen
      ].to_set.freeze

      Isolator = ::Module.new do
        def self.const_missing(name)
          ::Kernel.raise ::SecurityError,
            "[Aura Security] Constant `#{name}` is not accessible in the DSL. " \
            "Ruby runtime constants (File, ENV, Kernel, Object, etc.) are forbidden."
        end
      end

      def self.validate_constants!(source, allowed_constants)
        allowed = ::Set.new(allowed_constants.map(&:to_s))
        tokens = ::Ripper.lex(source)
        tokens.each_with_index do |tok, idx|
          _position, type, text = tok
          if type == :on_backtick
            ::Kernel.raise ::SecurityError,
              "[Aura Security] Shell interpolation is not accessible in the DSL."
          end

          if type == :on_ident && FORBIDDEN_METHODS.include?(text)
            ::Kernel.raise ::SecurityError,
              "[Aura Security] Method `#{text}` is not accessible in the DSL."
          end

          if type == :on_const

            prev_tok = idx > 0 ? tokens[idx - 1] : nil
            if prev_tok && prev_tok[1] == :on_symbeg
              next
            end

            next_tok = tokens[idx + 1]
            if next_tok && next_tok[1] == :on_symbeg && next_tok[2] == ":"
              next
            end

            unless allowed.include?(text)
              ::Kernel.raise ::SecurityError,
                "[Aura Security] Constant `#{text}` is not accessible in the DSL. " \
                "Ruby runtime constants (File, ENV, Kernel, Object, etc.) are forbidden."
            end
          end
        end
      end

      def self.compile_source(source, filename = "(eval)", capabilities = nil)
        allowed_keys = if capabilities
                         capabilities.allowed_constants.keys
                       else
                         ["RUBY_VERSION", "AURA_VERSION", "TRUE", "FALSE", "NIL"]
                       end

        validate_constants!(source, allowed_keys)

        wrapped = "::Kernel.proc do\n#{source}\nend"
        Isolator.module_eval(wrapped, filename, 0)
      rescue ::SyntaxError => e
        ::Kernel.raise ::SyntaxError, "[Aura DSL] Syntax error in `#{filename}`: #{e.message}"
      end
    end
  end
end
