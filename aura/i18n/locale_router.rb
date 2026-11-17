module Aura
  module I18n

    class LocaleRouter
      attr_reader :locales, :default

      def initialize(locales:, default: "en")
        @locales = Array(locales).map(&:to_s)
        @default = default.to_s
      end

      def strip_prefix(path)
        segments = segments_for(path)

        if segments.first && @locales.include?(segments.first)
          [segments.first, join(segments[1..])]
        else
          [@default, join(segments)]
        end
      end

      def localize(path, locale)
        locale = locale.to_s
        rest   = strip_prefix(path)[1]
        return rest if locale == @default || !@locales.include?(locale)

        rest == "/" ? prefix_for(locale) : "#{prefix_for(locale)}#{rest}"
      end

      def localized?(path)
        strip_prefix(path).first != @default
      end

      def prefix_for(locale)
        locale = locale.to_s
        return "" if locale == @default || !@locales.include?(locale)

        "/#{locale}"
      end

      def rewrite(path)
        locale, rest = strip_prefix(path)
        localize(rest, locale)
      end

      private

      def segments_for(path)
        path.to_s.split("/").reject(&:empty?)
      end

      def join(segments)
        return "/" if segments.nil? || segments.empty?

        "/" + segments.join("/")
      end
    end
  end
end
