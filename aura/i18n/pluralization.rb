module Aura
  module I18n

    module Pluralization
      def self.category(count, locale = "en")
        n = count.to_i.abs

        case normalize(locale)
        when "en"
          n == 1 ? :one : :other
        when "fr"
          (0..1).cover?(n) ? :one : :other
        when "ru", "uk"
          slavic(n)
        when "ar"
          arabic(n)
        else
          n == 1 ? :one : :other
        end
      end

      def self.select(count, locale, forms)
        return nil if forms.nil? || forms.empty?

        category = category(count, locale)
        forms[category] || forms[category.to_s] ||
          forms[:other] || forms["other"] ||
          forms.values.first
      end

      def self.slavic(n)
        mod10  = n % 10
        mod100 = n % 100

        return :one if mod10 == 1 && mod100 != 11
        return :few if (2..4).cover?(mod10) && !(12..14).cover?(mod100)
        return :many if mod10.zero? || (5..9).cover?(mod10) || (11..14).cover?(mod100)

        :other
      end

      def self.arabic(n)
        return :zero if n.zero?
        return :one if n == 1
        return :two if n == 2

        mod100 = n % 100
        return :few if (3..10).cover?(mod100)
        return :many if (11..99).cover?(mod100)

        :other
      end

      def self.normalize(locale)
        locale.to_s.downcase.split(/[-_]/).first
      end
    end
  end
end
