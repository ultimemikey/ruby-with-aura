module Aura
  module Web
    module SEO

      module Accessibility

        ELEMENTS = { "region" => "section" }.freeze

        def self.skip_link(target: "#main", label: "Skip to content")
          %(<a class="skip-link" href="#{escape(target)}">#{escape(label)}</a>)
        end

        def self.landmark(role, &block)
          inner = block ? block.call.to_s : ""
          landmark_tag(role, {}, inner)
        end

        def self.landmark_tag(role, attrs = {}, inner_html = "")
          role = role.to_s
          tag  = ELEMENTS.fetch(role, role)

          attributes = { "role" => role }.merge(attrs.transform_keys(&:to_s))
          attr_str   = attributes.map { |key, value| %( #{key}="#{escape(value)}") }.join

          "<#{tag}#{attr_str}>#{inner_html}</#{tag}>"
        end

        def self.live_region(content, politeness: "polite")
          %(<div aria-live="#{escape(politeness)}" aria-atomic="true">#{content}</div>)
        end

        def self.tabindex_order(*tags)
          tags.each_with_index.map { |tag, index| "#{tag}:#{index + 1}" }.join(" ")
        end

        def self.escape(value)
          value.to_s
               .gsub("&", "&amp;")
               .gsub("<", "&lt;")
               .gsub(">", "&gt;")
               .gsub('"', "&quot;")
        end
      end
    end
  end
end
