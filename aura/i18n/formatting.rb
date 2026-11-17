require "date"

module Aura
  module I18n

    module Formatting
      THOUSANDS = { "en" => ",", "fr" => " " }.freeze
      DECIMAL   = { "en" => ".", "fr" => "," }.freeze

      CURRENCY_SYMBOLS  = { "EUR" => "€", "USD" => "$", "GBP" => "£", "JPY" => "¥" }.freeze
      CURRENCY_DECIMALS = { "JPY" => 0 }.freeze

      MONTHS = {
        "en" => %w[January February March April May June July August September October November December],
        "fr" => %w[janvier février mars avril mai juin juillet août septembre octobre novembre décembre]
      }.freeze

      UNITS = {
        "en" => { second: %w[second seconds], minute: %w[minute minutes],
                  hour: %w[hour hours], day: %w[day days] },
        "fr" => { second: %w[seconde secondes], minute: %w[minute minutes],
                  hour: %w[heure heures], day: %w[jour jours] }
      }.freeze

      def self.number(value, locale = "en", precision: nil)
        return nil if value.nil?

        num = to_number(value)
        return nil if num.nil?

        formatted =
          if precision
            Kernel.format("%.#{precision.to_i}f", num)
          elsif num.is_a?(Integer) || num == num.to_i
            num.to_i.to_s
          else
            num.to_s
          end

        int_part, dec_part = formatted.split(".", 2)
        int_part = group_digits(int_part, locale)
        return int_part if dec_part.nil? || dec_part.empty?

        "#{int_part}#{decimal_separator(locale)}#{dec_part}"
      end

      def self.currency(value, code = "EUR", locale = "fr")
        return nil if value.nil?

        code      = code.to_s.upcase
        symbol    = CURRENCY_SYMBOLS.fetch(code, code)
        precision = CURRENCY_DECIMALS.fetch(code, 2)

        amount = number(value, locale, precision: precision)
        return nil if amount.nil?

        prefix?(locale) ? "#{symbol}#{amount}" : "#{amount} #{symbol}"
      end

      def self.date(time, locale = "en", format: :short)
        return nil if time.nil?

        moment = to_date_like(time)
        return nil if moment.nil?

        lang = base_locale(locale)

        case format.to_sym
        when :iso
          Kernel.format("%04d-%02d-%02d", moment.year, moment.month, moment.day)
        when :long
          month = MONTHS.fetch(lang, MONTHS["en"])[moment.month - 1]
          lang == "fr" ? "#{moment.day} #{month} #{moment.year}" : "#{month} #{moment.day}, #{moment.year}"
        else
          short_date(moment, lang)
        end
      end

      def self.relative(time, locale = "en", from: Time.now)
        return nil if time.nil?

        moment = to_time(time)
        return nil if moment.nil?

        reference = to_time(from) || Time.now
        seconds   = reference - moment
        future    = seconds.negative?
        value, unit = relative_unit(seconds.abs)

        phrase(value, unit, future, base_locale(locale))
      end

      def self.group_digits(digits, locale)
        sign = ""
        if digits.start_with?("-", "+")
          sign   = digits[0]
          digits = digits[1..] || ""
        end

        separator = thousands_separator(locale)
        digits.reverse.scan(/\d{1,3}/).join(separator).reverse.prepend(sign)
      end

      def self.thousands_separator(locale)
        THOUSANDS.fetch(base_locale(locale), THOUSANDS["en"])
      end

      def self.decimal_separator(locale)
        DECIMAL.fetch(base_locale(locale), DECIMAL["en"])
      end

      def self.prefix?(locale)
        base_locale(locale).start_with?("en")
      end

      def self.base_locale(locale)
        locale.to_s.downcase.split(/[-_]/).first
      end

      def self.short_date(moment, lang)
        if lang == "fr"
          Kernel.format("%02d/%02d/%04d", moment.day, moment.month, moment.year)
        else
          Kernel.format("%02d/%02d/%04d", moment.month, moment.day, moment.year)
        end
      end

      def self.relative_unit(seconds)
        if seconds >= 86_400
          [(seconds / 86_400).floor, :day]
        elsif seconds >= 3_600
          [(seconds / 3_600).floor, :hour]
        elsif seconds >= 60
          [(seconds / 60).floor, :minute]
        else
          [seconds.floor, :second]
        end
      end

      def self.phrase(value, unit, future, lang)
        words = (UNITS.fetch(lang, UNITS["en"])[unit] || UNITS["en"][unit])
        noun  = value == 1 ? words[0] : words[1]

        if lang == "fr"
          future ? "dans #{value} #{noun}" : "il y a #{value} #{noun}"
        else
          future ? "in #{value} #{noun}" : "#{value} #{noun} ago"
        end
      end

      def self.to_number(value)
        return value if value.is_a?(Numeric)
        return nil if value.nil?

        Float(value)
      rescue ArgumentError, TypeError
        nil
      end

      def self.to_date_like(value)
        case value
        when Time, Date, DateTime then value
        when Integer then Time.at(value)
        else
          value.respond_to?(:year) && value.respond_to?(:month) && value.respond_to?(:day) ? value : nil
        end
      end

      def self.to_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        return Time.at(value) if value.is_a?(Integer)
        return value.to_time if value.respond_to?(:to_time)
        return Time.new(value.year, value.month, value.day) if value.respond_to?(:year)

        nil
      end
    end
  end
end
