module Aura
  module Web
    module SEO

      module Social
        def self.tags(title: nil, description: nil, url: nil, image: nil,
                      type: "website", site_name: nil, twitter: nil)
          out = []

          {
            "og:title" => title,
            "og:description" => description,
            "og:url" => url,
            "og:image" => image,
            "og:type" => type,
            "og:site_name" => site_name
          }.each do |property, content|
            out << { property: property, content: content } unless content.nil?
          end

          {
            "twitter:card" => image ? "summary_large_image" : "summary",
            "twitter:site" => twitter,
            "twitter:title" => title,
            "twitter:description" => description,
            "twitter:image" => image
          }.each do |name, content|
            out << { name: name, content: content } unless content.nil?
          end

          out
        end

        def self.render(tags)
          Array(tags).map do |tag|
            key   = tag.key?(:property) ? "property" : "name"
            value = tag[:property] || tag[:name]
            %(<meta #{key}="#{escape(value)}" content="#{escape(tag[:content])}">)
          end.join("\n")
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
