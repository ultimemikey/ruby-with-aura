module Aura
  module Web
    module SEO

      module Sitemap
        def self.render(routes, base_url:, lastmod: nil)
          entries = routes.map do |path|
            loc = join(base_url, path)
            "<url><loc>#{escape(loc)}</loc>#{lastmod ? "<lastmod>#{escape(lastmod)}</lastmod>" : ""}</url>"
          end.join

          <<~XML
            <?xml version="1.0" encoding="UTF-8"?>
            <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{entries}</urlset>
          XML
        end

        def self.robots(base_url:, sitemap_path: "/sitemap.xml", disallow: [])
          lines = ["User-agent: *"]
          if disallow.empty?
            lines << "Allow: /"
          else
            disallow.each { |p| lines << "Disallow: #{p}" }
          end
          lines << "Sitemap: #{join(base_url, sitemap_path)}"
          lines.join("\n") + "\n"
        end

        def self.join(base_url, path)
          base_url.to_s.sub(%r{/+\z}, "") + (path.start_with?("/") ? path : "/#{path}")
        end

        def self.escape(str)
          str.to_s
             .gsub("&", "&amp;")
             .gsub("<", "&lt;")
             .gsub(">", "&gt;")
             .gsub('"', "&quot;")
        end
      end
    end
  end
end
