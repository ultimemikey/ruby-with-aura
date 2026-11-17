require "fileutils"
require "digest"

module Aura
  module Deploy

    module StaticExport
      DEFAULT_OUT = "dist"

      def self.export(root, router, out_dir: DEFAULT_OUT, spa_fallback: false)
        written = Aura::SSG::Exporter.new(router: router, out: out_dir, root: root).export

        dist = File.expand_path(out_dir, root)
        FileUtils.mkdir_p(dist)

        headers_path   = File.join(dist, "_headers")
        redirects_path = File.join(dist, "_redirects")

        File.write(headers_path, headers_file, mode: "w", encoding: "utf-8")
        File.write(redirects_path, redirects_file(spa_fallback: spa_fallback), mode: "w", encoding: "utf-8")

        written + [headers_path, redirects_path]
      end

      def self.cdn_manifest(out_dir)
        base = File.expand_path(out_dir)
        return {} unless File.directory?(base)

        manifest = {}
        Dir.glob(File.join(base, "**", "*")).sort.each do |path|
          next unless File.file?(path)

          relative = path.sub(base + File::SEPARATOR, "")
          manifest[relative] = "sha256-#{Digest::SHA256.file(path).hexdigest}"
        end
        manifest
      end

      def self.headers_file
        <<~HEADERS
          /assets/*
            Cache-Control: public, max-age=31536000, immutable

          /_aura/*
            Cache-Control: no-store

          /sitemap.xml
            Cache-Control: public, max-age=3600

          /robots.txt
            Cache-Control: public, max-age=3600
        HEADERS
      end

      def self.redirects_file(spa_fallback: false)
        if spa_fallback
          <<~REDIRECTS
            # SPA fallback: serve index.html for unmatched routes.
            /*  /index.html  200
          REDIRECTS
        else
          <<~REDIRECTS
            # No redirects configured. Enable the SPA fallback with spa_fallback: true.
          REDIRECTS
        end
      end
    end
  end
end
