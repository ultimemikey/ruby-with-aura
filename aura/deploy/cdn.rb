module Aura
  module Deploy

    class Cdn

      ATTRS = %w[src srcset poster href].freeze

      ASSET_PREFIXES = %w[/assets/ /_aura/ /static/ /images/ /fonts/ /media/].freeze

      ASSET_EXTENSIONS = %w[
        .css .js .mjs .map .json
        .png .jpg .jpeg .gif .svg .webp .avif .ico
        .woff .woff2 .ttf .otf .eot
        .mp4 .webm .mp3 .wav
      ].freeze

      attr_reader :asset_prefixes, :asset_extensions

      def initialize(asset_prefixes: ASSET_PREFIXES, asset_extensions: ASSET_EXTENSIONS)
        @asset_prefixes   = asset_prefixes
        @asset_extensions = asset_extensions
      end

      def rewrite(html, base_url)
        base = normalize(base_url)
        return html.to_s if base.empty?

        html.to_s.gsub(/\b(#{ATTRS.join('|')})\s*=\s*(["'])(.*?)\2/mi) do
          attr  = ::Regexp.last_match(1)
          quote = ::Regexp.last_match(2)
          value = ::Regexp.last_match(3)

          rewritten =
            if attr.downcase == "srcset"
              rewrite_srcset(value, base)
            elsif attr.downcase == "href"
              asset_like?(value) ? rewrite_url(value, base) : value
            else
              rewrite_url(value, base)
            end

          "#{attr}=#{quote}#{rewritten}#{quote}"
        end
      end

      def upload(dir, base_url)
        base  = normalize(base_url)
        root  = ::File.expand_path(dir.to_s)
        prefix = base.empty? ? "" : "#{base}/"

        ::Dir.glob(::File.join(root, "**", "*"))
             .select { |path| ::File.file?(path) }
             .sort
             .map { |path| "#{prefix}#{relative(path, root)}" }
      end

      private

      def rewrite_srcset(value, base)
        value.split(",").map do |candidate|
          part = candidate.strip
          next part if part.empty?

          url, *rest = part.split(/\s+/, 2)
          [rewrite_url(url, base), *rest].join(" ")
        end.join(", ")
      end

      def rewrite_url(value, base)
        raw = value.strip
        return value if raw.empty? || absolute?(raw) || !raw.start_with?("/")

        "#{base}#{raw}"
      end

      def absolute?(url)
        url.start_with?("//") || url.start_with?("#") || url.match?(/\A[a-z][a-z0-9+.-]*:/i)
      end

      def asset_like?(value)
        path = value.to_s.strip.split(/[?#]/, 2).first.to_s
        return true if asset_prefixes.any? { |prefix| path.start_with?(prefix) }

        ext = ::File.extname(path).downcase
        !ext.empty? && asset_extensions.include?(ext)
      end

      def normalize(base_url)
        base_url.to_s.strip.sub(%r{/+\z}, "")
      end

      def relative(path, root)
        path.sub(root + ::File::SEPARATOR, "")
      end
    end
  end
end
