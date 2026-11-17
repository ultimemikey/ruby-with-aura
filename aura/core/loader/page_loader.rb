require_relative "../parser/parser"

module Aura
  module Core
    module Loader
      class PageLoader
        def self.load(path, session = {}, cookies = {}, params = {}, layout_files: [], loading_file: nil, i18n: nil, locale: nil, query: {}, fragment: nil)
          parser = Parser.new(
            session, cookies, params,
            layout_files: layout_files,
            loading_file: loading_file,
            i18n: i18n,
            locale: locale,
            query: query,
            fragment: fragment
          )
          doc = parser.parse(path)
          [doc, parser]
        end
      end
    end
  end
end
