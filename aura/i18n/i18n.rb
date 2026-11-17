require "json"

module Aura
  module I18n
    DEFAULT_LOCALE = "en"

    class Catalog
      attr_reader :root, :locale, :messages

      def self.load(root, locale = nil)
        new(root, locale)
      end

      def initialize(root, locale = nil)
        @root     = root
        @locale   = normalize_locale(root, locale)
        @messages = self.class.read(@root, @locale)
      end

      def t(key, **vars)
        template = @messages[key.to_s]
        return key.to_s if template.nil?

        vars.reduce(template.to_s) { |acc, (k, v)| acc.gsub("%{#{k}}", v.to_s) }
      end

      def available
        self.class.available_locales(@root)
      end

      def self.negotiate(root:, explicit: nil, cookie: nil, accept_language: nil)
        supported = available_locales(root)
        return DEFAULT_LOCALE if supported.empty?

        [explicit, cookie, from_header(accept_language, supported)]
          .map(&:to_s)
          .find { |candidate| supported.include?(candidate) } || supported.first
      end

      def self.available_locales(root)
        dir = ::File.join(root, "app", "locales")
        return [] unless ::Dir.exist?(dir)

        ::Dir.children(dir).filter_map { |f| f[/\A(.+)\.json\z/, 1] }.sort
      end

      def self.from_header(header, supported)
        return nil if header.nil? || header.empty?

        header.split(",")
              .map { |part| part.split(";").first.to_s.strip.downcase.split("-").first }
              .find { |code| supported.include?(code) }
      end

      def self.read(root, locale)
        path = ::File.join(root, "app", "locales", "#{locale}.json")
        return {} unless ::File.file?(path)

        ::JSON.parse(::File.read(path, encoding: "utf-8"))
      rescue ::JSON::ParserError
        {}
      end

      private

      def normalize_locale(root, locale)
        candidate = locale.to_s
        supported = self.class.available_locales(root)

        return candidate if supported.include?(candidate)

        DEFAULT_LOCALE
      end
    end
  end
end
