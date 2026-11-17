module Aura
  module Assets

    module CssPipeline
      module_function

      def process(css, minify: false, variables: {})
        cleaned, inline = extract_variables(css.to_s)
        vars = normalize_variables(variables).merge(inline)

        expanded = substitute(cleaned, vars)
        rules = flatten(expanded, nil)
        out = rules.empty? ? expanded : rules.join("\n")

        minify ? self.minify(out) : out.strip
      end

      def minify(css)
        without_comments = css.to_s.gsub(%r{/\*.*?\*/}m, "")

        split_strings(without_comments)
          .map { |kind, text| kind == :string ? text : tighten(text) }
          .join
          .strip
      end

      def extract_variables(css)
        vars = {}

        cleaned = css.gsub(/\$([\w-]+)\s*:\s*([^;{}]+);\s*/) do
          vars[::Regexp.last_match(1)] = ::Regexp.last_match(2).strip
          ""
        end

        [cleaned, vars]
      end

      def normalize_variables(variables)
        variables.each_with_object({}) do |(key, value), acc|
          acc[key.to_s.sub(/\A\$/, "")] = value.to_s
        end
      end

      def substitute(css, vars)
        vars.keys.sort_by { |k| -k.length }.reduce(css) do |acc, key|
          acc.gsub(/\$#{::Regexp.escape(key)}\b/) { vars[key] }
        end
      end

      def flatten(css, parent)
        out  = []
        rest = css.to_s

        loop do
          brace = rest.index("{")
          break if brace.nil?

          selector = rest[0...brace].strip
          close    = matching_brace(rest, brace)
          body     = rest[(brace + 1)...close]
          rest     = rest[(close + 1)..] || ""

          if selector.start_with?("@")
            inner = flatten(body, nil)
            out << "#{selector} { #{inner.join(' ')} }"
            next
          end

          combined = combine(parent, selector)
          decls, nested = split_body(body)

          out << "#{combined} { #{decls.strip} }" unless decls.strip.empty?

          nested.each do |nested_selector, nested_body|
            out.concat(flatten("#{nested_selector} {#{nested_body}}", combined))
          end
        end

        out
      end

      def combine(parent, selector)
        flat = selector.split(",").map(&:strip).reject(&:empty?)
        return selector.strip if parent.nil?

        flat.map { |part| part.include?("&") ? part.gsub("&", parent) : "#{parent} #{part}" }.join(", ")
      end

      def split_body(body)
        decls  = +""
        nested = []
        i      = 0

        while i < body.length
          if body[i] == "{"
            close    = matching_brace(body, i)
            boundary = decls.rindex(";")

            if boundary
              selector = decls[(boundary + 1)..].strip
              decls    = decls[0..boundary]
            else
              selector = decls.strip
              decls    = +""
            end

            nested << [selector, body[(i + 1)...close]]
            i = close + 1
          else
            decls << body[i]
            i += 1
          end
        end

        [decls, nested]
      end

      def matching_brace(str, open_index)
        depth = 0
        i     = open_index

        while i < str.length
          depth += 1 if str[i] == "{"
          depth -= 1 if str[i] == "}"
          return i if depth.zero?

          i += 1
        end

        str.length - 1
      end

      def split_strings(css)
        segments = []
        buffer   = +""
        i        = 0

        while i < css.length
          if css[i] == '"' || css[i] == "'"
            segments << [:code, buffer] unless buffer.empty?
            buffer = +""
            str, i = read_string(css, i)
            segments << [:string, str]
          else
            buffer << css[i]
            i += 1
          end
        end

        segments << [:code, buffer] unless buffer.empty?
        segments
      end

      def read_string(css, i)
        quote = css[i]
        out   = quote.dup
        i    += 1

        while i < css.length
          ch = css[i]
          out << ch

          if ch == "\\"
            out << css[i + 1].to_s
            i += 2
            next
          elsif ch == quote
            i += 1
            break
          end

          i += 1
        end

        [out, i]
      end

      def tighten(code)
        code.gsub(/\s+/, " ")
            .gsub(/\s*([{};:,>+~])\s*/) { ::Regexp.last_match(1) }
            .gsub(/;\}/, "}")
      end
    end
  end
end
