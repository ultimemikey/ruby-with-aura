module Aura
  module Assets

    module Fonts

      MIME_TYPES = {
        "woff2" => "font/woff2",
        "woff"  => "font/woff",
        "ttf"   => "font/ttf",
        "otf"   => "font/otf",
        "eot"   => "application/vnd.ms-fontobject"
      }.freeze

      module_function

      def font_face(family:, src:, weight: "400", display: "swap")
        <<~CSS.chomp
          @font-face {
            font-family: "#{family}";
            src: #{sources(src)};
            font-weight: #{weight};
            font-display: #{display};
          }
        CSS
      end

      def preload_tags(paths)
        Array(paths).map do |path|
          type = MIME_TYPES[::File.extname(path.to_s).sub(/\A\./, "").downcase] || "font/woff2"
          %(<link rel="preload" href="#{path}" as="font" type="#{type}" crossorigin>)
        end
      end

      def sources(src)
        case src
        when ::Hash
          src.map { |format, url| "url(\"#{url}\") format(\"#{format}\")" }.join(", ")
        when ::Array
          src.map { |url| "url(\"#{url}\")" }.join(", ")
        else
          "url(\"#{src}\")"
        end
      end
    end
  end
end
