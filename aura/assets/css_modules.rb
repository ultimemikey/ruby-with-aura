require "digest"

module Aura
  module Assets

    module CssModules
      module_function

      def scope(css, scope)
        mapping = {}

        scoped = css.to_s.gsub(/([^{}]+)(\{)/) do
          selector = ::Regexp.last_match(1)
          brace    = ::Regexp.last_match(2)

          rewritten = selector.gsub(/\.([A-Za-z_][\w-]*)/) do
            name = ::Regexp.last_match(1)
            mapping[name] ||= "#{scope}-#{hash8(name)}"
            ".#{mapping[name]}"
          end

          "#{rewritten}#{brace}"
        end

        [scoped, mapping]
      end

      def hash8(name)
        Digest::SHA256.hexdigest(name.to_s)[0, 8]
      end
    end
  end
end
