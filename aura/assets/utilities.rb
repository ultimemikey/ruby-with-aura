module Aura
  module Assets

    module Utilities
      module_function

      SCALE = {
        "0" => "0",      "1" => "0.25rem", "2" => "0.5rem",  "3" => "0.75rem",
        "4" => "1rem",   "5" => "1.25rem", "6" => "1.5rem",  "8" => "2rem",
        "10" => "2.5rem", "12" => "3rem"
      }.freeze

      SPACING = {
        "p"  => %w[padding],
        "px" => %w[padding-left padding-right],
        "py" => %w[padding-top padding-bottom],
        "pt" => %w[padding-top],
        "pr" => %w[padding-right],
        "pb" => %w[padding-bottom],
        "pl" => %w[padding-left],
        "m"  => %w[margin],
        "mx" => %w[margin-left margin-right],
        "my" => %w[margin-top margin-bottom],
        "mt" => %w[margin-top],
        "mr" => %w[margin-right],
        "mb" => %w[margin-bottom],
        "ml" => %w[margin-left]
      }.freeze

      GRAYS = {
        "100" => "#f3f4f6", "200" => "#e5e7eb", "300" => "#d1d5db",
        "400" => "#9ca3af", "500" => "#6b7280", "600" => "#4b5563",
        "700" => "#374151", "800" => "#1f2937", "900" => "#111827"
      }.freeze

      STATIC = {

        "flex" => "display: flex;",
        "inline-flex" => "display: inline-flex;",
        "grid" => "display: grid;",
        "block" => "display: block;",
        "inline-block" => "display: inline-block;",
        "hidden" => "display: none;",
        "items-center" => "align-items: center;",
        "items-start" => "align-items: flex-start;",
        "items-end" => "align-items: flex-end;",
        "justify-center" => "justify-content: center;",
        "justify-between" => "justify-content: space-between;",
        "justify-start" => "justify-content: flex-start;",
        "justify-end" => "justify-content: flex-end;",
        "flex-col" => "flex-direction: column;",
        "flex-row" => "flex-direction: row;",
        "flex-1" => "flex: 1 1 0%;",

        "w-full" => "width: 100%;",
        "w-auto" => "width: auto;",
        "h-full" => "height: 100%;",
        "h-auto" => "height: auto;",
        "max-w-full" => "max-width: 100%;",
        "min-h-full" => "min-height: 100%;",

        "text-xs" => "font-size: 0.75rem; line-height: 1rem;",
        "text-sm" => "font-size: 0.875rem; line-height: 1.25rem;",
        "text-base" => "font-size: 1rem; line-height: 1.5rem;",
        "text-lg" => "font-size: 1.125rem; line-height: 1.75rem;",
        "text-xl" => "font-size: 1.25rem; line-height: 1.75rem;",
        "text-2xl" => "font-size: 1.5rem; line-height: 2rem;",
        "text-3xl" => "font-size: 1.875rem; line-height: 2.25rem;",
        "text-center" => "text-align: center;",
        "text-left" => "text-align: left;",
        "text-right" => "text-align: right;",
        "font-bold" => "font-weight: 700;",
        "font-semibold" => "font-weight: 600;",
        "font-medium" => "font-weight: 500;",
        "font-normal" => "font-weight: 400;",
        "uppercase" => "text-transform: uppercase;",
        "lowercase" => "text-transform: lowercase;",
        "capitalize" => "text-transform: capitalize;",
        "italic" => "font-style: italic;",
        "truncate" => "overflow: hidden; text-overflow: ellipsis; white-space: nowrap;",

        "text-white" => "color: #ffffff;",
        "text-black" => "color: #000000;",
        "bg-white" => "background-color: #ffffff;",
        "bg-black" => "background-color: #000000;",
        "bg-transparent" => "background-color: transparent;",

        "rounded" => "border-radius: 0.25rem;",
        "rounded-sm" => "border-radius: 0.125rem;",
        "rounded-md" => "border-radius: 0.375rem;",
        "rounded-lg" => "border-radius: 0.5rem;",
        "rounded-full" => "border-radius: 9999px;",
        "border" => "border-width: 1px;",
        "border-0" => "border-width: 0px;",
        "border-2" => "border-width: 2px;",

        "shadow" => "box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1), 0 1px 2px -1px rgba(0, 0, 0, 0.1);",
        "shadow-sm" => "box-shadow: 0 1px 2px 0 rgba(0, 0, 0, 0.05);",
        "shadow-md" => "box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -2px rgba(0, 0, 0, 0.1);",
        "shadow-lg" => "box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -4px rgba(0, 0, 0, 0.1);",
        "opacity-0" => "opacity: 0;",
        "opacity-25" => "opacity: 0.25;",
        "opacity-50" => "opacity: 0.5;",
        "opacity-75" => "opacity: 0.75;",
        "opacity-100" => "opacity: 1;",

        "mx-auto" => "margin-left: auto; margin-right: auto;",
        "container" => "width: 100%; margin-left: auto; margin-right: auto;"
      }.freeze

      KNOWN = (
        STATIC.keys + %w[
          p-4 px-2 py-1 pt-3 pr-4 pb-2 pl-1
          m-0 mx-auto my-2 mt-4 mr-1 mb-6 ml-3
          gap-6 p-[12px] m-[auto] w-4 h-8 w-[40%] h-[50vh]
          text-gray-500 bg-gray-100
        ]
      ).dup.freeze

      def css(classes)
        names(classes).uniq.filter_map { |name| rule(name) }.join("\n")
      end

      def scan(source)
        source.to_s.scan(TOKEN).select { |name| recognise?(name) }.uniq.sort
      end

      def recognise?(name)
        !rule(name).nil?
      end

      def known
        KNOWN
      end

      TOKEN = /[A-Za-z][A-Za-z0-9_-]*(?:\[[^\]\s"'<>{};]+\])?/

      def names(classes)
        case classes
        when ::Array then classes.flat_map { |c| c.to_s.split(/\s+/) }.reject(&:empty?)
        when ::String then classes.split(/\s+/).reject(&:empty?)
        else Array(classes).map(&:to_s).reject(&:empty?)
        end
      end

      def rule(name)
        name = name.to_s
        return nil if name.empty?
        return "#{selector(name)} { #{STATIC[name]} }" if STATIC.key?(name)

        spacing_rule(name) || sizing_rule(name) || gap_rule(name) || color_rule(name)
      end

      def spacing_rule(name)
        match = name.match(/\A(p[xytrbl]?|m[xytrbl]?)-(.+)\z/)
        return nil unless match

        value = value_for(match[2], allow_auto: match[1].start_with?("m"))
        return nil unless value

        "#{selector(name)} { #{declarations(SPACING[match[1]], value)} }"
      end

      def sizing_rule(name)
        match = name.match(/\A([wh])-(.+)\z/)
        return nil unless match

        value = value_for(match[2], allow_auto: true, allow_full: true)
        return nil unless value

        property = match[1] == "w" ? "width" : "height"
        "#{selector(name)} { #{property}: #{value}; }"
      end

      def gap_rule(name)
        match = name.match(/\Agap-(.+)\z/)
        return nil unless match

        value = value_for(match[1])
        return nil unless value

        "#{selector(name)} { gap: #{value}; }"
      end

      def color_rule(name)
        match = name.match(/\A(text|bg)-gray-(\d+)\z/)
        return nil unless match

        hex = GRAYS[match[2]]
        return nil unless hex

        property = match[1] == "text" ? "color" : "background-color"
        "#{selector(name)} { #{property}: #{hex}; }"
      end

      def value_for(token, allow_auto: false, allow_full: false)
        return nil if token.nil? || token.empty?

        return sanitize(token[1...-1]) if token.start_with?("[") && token.end_with?("]")
        return SCALE[token] if SCALE.key?(token)
        return "1px" if token == "px"
        return "auto" if token == "auto" && allow_auto
        return "100%" if token == "full" && allow_full

        nil
      end

      def sanitize(value)
        cleaned = value.to_s.gsub(/[^A-Za-z0-9.%_+\-#()\/, ]/, "").strip
        cleaned.empty? ? nil : cleaned
      end

      def declarations(properties, value)
        properties.map { |property| "#{property}: #{value};" }.join(" ")
      end

      def selector(name)
        ".#{escape_class(name)}"
      end

      def escape_class(name)
        name.gsub(/([^A-Za-z0-9_-])/) { "\\#{::Regexp.last_match(1)}" }
      end
    end
  end
end
