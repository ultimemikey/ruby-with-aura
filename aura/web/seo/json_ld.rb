require "json"

module Aura
  module Web
    module SEO

      module JsonLd
        CONTEXT = "https://schema.org"

        def self.article(title:, description:, url:, author: nil, date_published: nil, image: nil)
          data = base("Article")
          data["headline"]    = title
          data["description"] = description
          data["url"]         = url
          data["author"]      = { "@type" => "Person", "name" => author } if author
          data["datePublished"] = date_published.to_s if date_published
          data["image"] = image if image
          data
        end

        def self.product(name:, description:, price:, currency:, url:, availability: "InStock", rating: nil)
          data = base("Product")
          data["name"]        = name
          data["description"] = description
          data["url"]         = url
          data["offers"] = {
            "@type" => "Offer",
            "price" => price,
            "priceCurrency" => currency,
            "url" => url,
            "availability" => availability_url(availability)
          }
          data["aggregateRating"] = { "@type" => "AggregateRating", "ratingValue" => rating } if rating
          data
        end

        def self.organization(name:, url:, logo: nil)
          data = base("Organization")
          data["name"] = name
          data["url"]  = url
          data["logo"] = logo if logo
          data
        end

        def self.breadcrumb(items)
          list = Array(items).each_with_index.map do |(name, url), index|
            { "@type" => "ListItem", "position" => index + 1, "name" => name, "item" => url }
          end
          base("BreadcrumbList").merge("itemListElement" => list)
        end

        def self.script_tag(data)
          json = ::JSON.generate(data).gsub("</") { "<\\/" }
          %(<script type="application/ld+json">#{json}</script>)
        end

        def self.combine(*hashes)
          graph = hashes.compact.map { |hash| hash.reject { |key, _| key == "@context" } }
          { "@context" => CONTEXT, "@graph" => graph }
        end

        def self.base(type)
          { "@context" => CONTEXT, "@type" => type }
        end

        def self.availability_url(availability)
          value = availability.to_s
          value.start_with?("http") ? value : "#{CONTEXT}/#{value}"
        end
      end
    end
  end
end
