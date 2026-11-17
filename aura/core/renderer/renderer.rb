require "json"
require_relative "html_renderer"
require_relative "../ui/slot"
require_relative "../ast/nodes"
require_relative "../../security/capability_context"
require_relative "../../core/dsl/execution_context"

module Aura
  module Core
    module Renderer
      class Renderer

        def self.render(doc, parser)
          resolved_doc = resolve_document(doc, parser)

          resolve_suspense!(resolved_doc, parser)

          assemble(resolved_doc)
        end

        def self.render_stream(doc, parser)
          resolved_doc = resolve_document(doc, parser)

          blocks = resolved_doc.respond_to?(:suspense_blocks) ? resolved_doc.suspense_blocks : {}

          return [assemble(resolved_doc)].each if blocks.empty?

          compiler = parser.instance_variable_get(:@compiler)

          ::Enumerator.new do |yielder|
            opening, closing = assemble_parts(resolved_doc)
            yielder << opening
            blocks.each_key { |id| yielder << suspense_chunk(id, compiler) }
            yielder << closing
          end
        end

        def self.resolve_document(doc, parser)
          capabilities = parser.instance_variable_get(:@capabilities) ||
                         Security::CapabilityContext.default

          if parser.respond_to?(:rebuild_ast!)
            rebuilt = parser.rebuild_ast!

            if doc.respond_to?(:csrf_token) && !rebuilt.respond_to?(:csrf_token)
              csrf_val = doc.csrf_token
              rebuilt.define_singleton_method(:csrf_token) { csrf_val }
            end
            rebuilt
          else
            DSL::ExecutionContext.new(
              capabilities: capabilities,
              session:      parser.session,
              cookies:      parser.cookies,
              params:       parser.params,
              components:   parser.components,
              layouts:      parser.layouts
            ).resolve(doc)
          end
        end

        def self.resolve_suspense!(resolved_doc, parser)
          return unless resolved_doc.respond_to?(:suspense_blocks)

          compiler = parser.instance_variable_get(:@compiler)
          return unless compiler

          resolved_doc.suspense_blocks.each_key { |id| compiler.resolve_suspense(id) }
        end

        def self.suspense_chunk(id, compiler)
          node  = compiler.resolve_suspense(id)
          inner = node ? HtmlRenderer.render_children(node) : ""
          key   = esc(id.to_s)

          %(<template data-aura-suspense-chunk="#{key}">#{inner}</template>) \
            "<script>window.__aura&&window.__aura.suspense&&window.__aura.suspense(#{::JSON.generate(id.to_s)});</script>" \
            "<!--aflush-->"
        end

        def self.assemble(doc)
          assemble_parts(doc).join
        end

        def self.assemble_parts(doc)
          if ast_has_tag?(doc, "html")

            html = inject_head(HtmlRenderer.render(doc), doc)
            idx  = html.rindex("</body>")
            return ["<!DOCTYPE html>\n#{html}", ""] if idx.nil?

            return ["<!DOCTYPE html>\n#{html[0...idx]}", html[idx..]]
          end

          body_html = HtmlRenderer.render(doc)
          head      = head_html(doc)
          lang      = esc(doc.lang || "en")

          if ast_direct_body?(doc)

            [<<~HTML, "</html>\n"]
              <!DOCTYPE html>
              <html lang="#{lang}">
              <head>
                #{head}
              </head>
              #{body_html}
            HTML
          else

            [<<~HTML, "</body>\n</html>\n"]
              <!DOCTYPE html>
              <html lang="#{lang}">
              <head>
                #{head}
              </head>
              <body>
                #{body_html}
            HTML
          end
        end

        def self.inject_head(html, doc)
          head = head_html(doc)
          html.sub("</head>", "#{head}\n</head>")
              .then { |h| h.include?("</head>") ? h : h.sub("<head>", "<head>\n#{head}") }
        end

        private

        def self.ast_has_tag?(doc, tag)
          return false unless doc.respond_to?(:children) && doc.children
          doc.children.any? { |n| n.is_a?(AST::ElementNode) && n.tag == tag }
        end

        def self.ast_direct_body?(doc)
          return false unless doc.respond_to?(:children) && doc.children
          first = doc.children.find { |n| n.is_a?(AST::ElementNode) }
          first && first.tag == "body"
        end

        def self.head_html(doc)
          tags = []
          tags << '<meta charset="UTF-8">'
          tags << '<meta name="viewport" content="width=device-width, initial-scale=1.0">'
          tags << "<title>#{esc(doc.title)}</title>" if doc.title

          if doc.seo
            tags << %(<meta name="description" content="#{esc(doc.seo[:description])}">) if doc.seo[:description]
            tags << %(<link rel="canonical" href="#{esc(doc.seo[:canonical])}">) if doc.seo[:canonical]
            if doc.seo[:og]
              doc.seo[:og].each do |k, v|
                tags << %(<meta property="og:#{esc(k)}" content="#{esc(v)}">)
              end
            end
            if doc.seo[:twitter]
              doc.seo[:twitter].each do |k, v|
                next if v.nil?

                name = k.to_s.start_with?("twitter:") ? k.to_s : "twitter:#{k}"
                tags << %(<meta name="#{esc(name)}" content="#{esc(v)}">)
              end
            end
            if doc.seo[:keywords]
              keywords = Array(doc.seo[:keywords]).join(", ")
              tags << %(<meta name="keywords" content="#{esc(keywords)}">)
            end
            tags << %(<meta name="robots" content="#{esc(doc.seo[:robots])}">) if doc.seo[:robots]
            json_ld = doc.seo[:json_ld]
            json_ld = [json_ld] unless json_ld.nil? || json_ld.is_a?(Array)
            Array(json_ld).each do |data|
              json = ::JSON.generate(data).gsub("</") { "<\\/" }
              tags << %(<script type="application/ld+json">#{json}</script>)
            end
          end

          doc.meta_tags.each do |m|
            next unless m.is_a?(Hash)
            attrs = m.map { |k, v| "#{esc(k)}=\"#{esc(v)}\"" }.join(" ")
            tags << "<meta #{attrs}>"
          end

          tags << %(<link rel="icon" type="image/png" href="#{esc(doc.assets.favicon)}">) if doc.assets.favicon

          doc.assets.css.each do |css|
            tags << %(<link rel="stylesheet" href="/#{esc(css)}">)
          end

          if doc.respond_to?(:styles)
            doc.styles.each do |css|
              tags << "<style data-aura-style>#{safe_css(css)}</style>"
            end
          end

          doc.assets.scripts.each do |s|
            tags << %(<script src="/#{esc(s)}"></script>)
          end

          csrf_js = doc.respond_to?(:csrf_token) && doc.csrf_token ? ::JSON.generate(doc.csrf_token) : "null"

          tags << "<script>window.__AURA_CSRF = #{csrf_js};</script>"
          tags << %(<script src="/_aura/client.js" defer></script>)

          tags.join("\n    ")
        end

        def self.esc(str)
          AttributeRenderer.escape_html(str)
        end

        def self.safe_css(css)
          css.to_s.gsub("</", "<\\/")
        end
      end
    end
  end
end
