require "fileutils"
require_relative "../deploy/cdn"

module Aura
  module SSG

    class Exporter
      attr_reader :out

      def initialize(router:, out: "dist", root: Dir.pwd, session: {}, cookies: {}, cdn: nil)
        @router  = router
        @out     = ::File.expand_path(out, root)
        @session = session
        @cookies = cookies
        @cdn     = cdn
      end

      def export
        written = []

        @router.static_pages.each do |url, file|
          html   = render(file)
          target = target_path(url)
          ::FileUtils.mkdir_p(::File.dirname(target))
          ::File.write(target, html, mode: "w", encoding: "utf-8")
          written << target
        end

        written
      end

      private

      def render(file)
        rewrite_cdn(render_page(file))
      end

      def rewrite_cdn(html)
        return html if @cdn.nil? || @cdn.to_s.empty?

        ::Aura::Deploy::Cdn.new.rewrite(html, @cdn)
      end

      def render_page(file)
        abs = ::File.expand_path(file)

        doc, parser = Core::Loader::PageLoader.load(
          abs, @session, @cookies, {},
          layout_files: @router.layout_chain(abs),
          loading_file: @router.loading_file_for(abs)
        )

        if (entry = doc.handlers[:mount])
          handler = entry.is_a?(::Hash) ? entry[:handler] : entry
          handler.call if handler
        end

        Core::Renderer::Renderer.render(doc, parser)
      end

      def target_path(url)
        clean = url.to_s.sub(%r{\A/+}, "")
        return ::File.join(@out, "index.html") if clean.empty?

        ::File.join(@out, clean, "index.html")
      end
    end
  end
end
