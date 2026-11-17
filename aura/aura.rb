require_relative "security/capability_context"
require_relative "security/constant_sandbox"

require_relative "config"
require_relative "secrets"

require_relative "core/ast/nodes"
require_relative "core/ast/validator"

require_relative "core/cache/store"
require_relative "core/forms/validator"

require_relative "db/db"
require_relative "auth/auth"

require_relative "i18n/i18n_ext"

require_relative "core/parser/nodes/node"
require_relative "core/parser/nodes/document"
require_relative "core/parser/nodes/element"
require_relative "core/parser/nodes/text"

require_relative "error/index"

require_relative "dev/dev"

require_relative "assets/assets"

require_relative "core/ui/slot"
require_relative "core/ui/component"
require_relative "core/ui/include"
require_relative "core/ui/layout"

require_relative "core/dsl/compiler"
require_relative "core/dsl/execution_context"

require_relative "core/parser/context"
require_relative "core/parser/parser"

require_relative "core/renderer/attribute_renderer"
require_relative "core/renderer/html_renderer"
require_relative "core/renderer/renderer"

require_relative "core/loader/page_loader"
require_relative "core/loader/include_loader"
require_relative "core/loader/component_loader"

require_relative "web/router/route"
require_relative "web/router/matcher"
require_relative "web/router/router"
require_relative "web/middleware/security_headers"
require_relative "web/middleware/rate_limiter"
require_relative "web/seo/sitemap"
require_relative "web/seo/seo_ext"
require_relative "web/server/request"
require_relative "web/server/response"
require_relative "web/server/server"

require_relative "deploy/deploy"

require_relative "ssg/exporter"

require_relative "error/error"

module Aura
  VERSION = "1.0.0"

  def self.env
    ENV.fetch("AURA_ENV") { ENV.fetch("RACK_ENV", "development") }
  end

  def self.config(root = Dir.pwd)
    Config.load(root)
  end

  module Engine

    def self.render(file, session = {}, cookies = {})
      doc, parser = Core::Loader::PageLoader.load(file, session, cookies)

      if (entry = doc.handlers[:mount])
        mount_handler = entry.is_a?(Hash) ? entry[:handler] : entry
        mount_handler.call if mount_handler
      end

      Core::Renderer::Renderer.render(doc, parser)
    end
  end

  def self.new_app
    router = Web::Router::Router.new
    server = Web::Server::Server.new(router)
    [router, server]
  end
end
