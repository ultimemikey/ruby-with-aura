require "json"

module Aura
  module Core
    module Renderer
      class AttributeRenderer
        BOOLEAN_ATTRIBUTES = %w[
          disabled checked readonly required multiple autofocus loop autoplay controls muted
        ].freeze

        def self.render(attrs)
          return "" if attrs.nil? || attrs.empty?

          rendered = attrs.map do |k, v|
            key = k.to_s

            if key.start_with?("on")
              handler = v.to_s

              unless handler.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
                raise "Invalid event handler name: #{handler.inspect}"
              end

              js_handler = JSON.generate(handler)

              "#{escape_html(key)}='auraCall(#{js_handler}, event)'"

            elsif BOOLEAN_ATTRIBUTES.include?(key)
              v ? key : nil
            elsif (key == "href" || key == "src") && v.to_s.gsub(/\s+/, "").downcase.start_with?("javascript:")
              "#{key}=\"#\""
            else
              "#{key}=\"#{escape_html(v)}\""
            end
          end.compact.join(" ")

          rendered.empty? ? "" : " #{rendered}"
        end

        def self.escape_html(str)
          str.to_s
             .gsub('&', '&amp;')
             .gsub('"', '&quot;')
             .gsub("'", '&#39;')
             .gsub('<', '&lt;')
             .gsub('>', '&gt;')
        end
      end
    end
  end
end

