require "json"
require "fileutils"
require "pathname"

module Aura
  module Assets

    module Bundler

      class MissingImport < StandardError; end

      module_function

      def bundle(entry_path, out: nil, minify: false)
        entry = ::File.expand_path(entry_path.to_s)
        raise MissingImport, "Entry not found: #{entry_path}" unless ::File.file?(entry)

        base    = ::File.dirname(entry)
        visited = {}
        order   = []
        collect(entry, visited, order)

        code = emit(order, entry, base)
        code = self.minify(code) if minify

        if out
          target = ::File.expand_path(out.to_s)
          ::FileUtils.mkdir_p(::File.dirname(target))
          ::File.write(target, code, mode: "w", encoding: "utf-8")
        end

        code
      end

      def minify(js)
        segments = split_segments(js)
        segments.map { |kind, text| kind == :string ? text : minify_code(text) }.join.strip
      end

      def collect(path, visited, order)
        return if visited[path]

        visited[path] = true
        source = ::File.read(path, encoding: "utf-8")

        relative_specifiers(source).each do |spec|
          collect(resolve_import(spec, path), visited, order)
        end

        order << [path, source]
      end

      def emit(order, entry, base)
        lines = []
        lines << "(function (__global) {"
        lines << "  var __registry = {};"
        lines << "  var __cache = {};"
        lines << "  function __require(id) {"
        lines << "    if (__cache[id]) return __cache[id].exports;"
        lines << "    var __module = (__cache[id] = { exports: {} });"
        lines << "    __registry[id](__module, __module.exports, __require);"
        lines << "    return __module.exports;"
        lines << "  }"

        order.each do |path, source|
          id = module_id(path, base)
          lines << "  __registry[#{js_string(id)}] = function (__module, __exports, __require) {"
          lines << transform(source, path, base)
          lines << "  };"
        end

        lines << "  __require(#{js_string(module_id(entry, base))});"
        lines << "})(typeof globalThis !== 'undefined' ? globalThis : this);"
        lines.join("\n") + "\n"
      end

      def transform(source, current, base)
        source.lines.map { |line| transform_line(line, current, base) }.join
      end

      def transform_line(line, current, base)
        indent = line[/\A[ \t]*/]

        if (m = line.match(/\A[ \t]*import\s+(['"])(.+?)\1\s*;?[ \t]*\r?\n?\z/))
          return line unless relative?(m[2])

          return "#{indent}#{reference(m[2], current, base)};\n"
        end

        if (m = line.match(/\A[ \t]*import\s+(.+?)\s+from\s+(['"])(.+?)\2\s*;?[ \t]*\r?\n?\z/))
          return line unless relative?(m[3])

          ref = reference(m[3], current, base)
          return "#{indent}#{bindings(m[1], ref)}\n"
        end

        if (m = line.match(/\A[ \t]*export\s+default\s+(.+?)[ \t]*;?[ \t]*\r?\n?\z/))
          return "#{indent}__exports.default = #{m[1].sub(/;\s*\z/, '')};\n"
        end

        if (m = line.match(/\A[ \t]*export\s*\{(.*)\}\s*(?:from\s+(['"])(.+?)\2)?\s*;?[ \t]*\r?\n?\z/m))
          spec = m[3]
          return line if spec && !relative?(spec)

          ref = spec ? reference(spec, current, base) : nil
          return "#{indent}#{export_list(m[1], ref)}\n"
        end

        if (m = line.match(/\A([ \t]*)export\s+(const|let|var)\s+([A-Za-z_$][\w$]*)(.*)\z/m))
          rest = line.sub(/\A([ \t]*)export\s+/, "\\1").chomp
          name = m[3]
          return "#{rest} __exports.#{name} = #{name};\n"
        end

        if (m = line.match(/\A([ \t]*)export\s+(async\s+)?(function|class)\b(.*)\z/m))
          return "#{m[1]}#{m[2]}#{m[3]}#{m[4].chomp}\n"
        end

        line
      end

      def bindings(str, ref)
        str = str.strip

        if str.start_with?("{")
          named_imports(str[/\{(.*)\}/m, 1].to_s, ref)
        elsif str.start_with?("*")
          "var #{str.sub(/\A\*\s+as\s+/, '').strip} = #{ref};"
        elsif (comma = str.index(","))
          default = str[0...comma].strip
          rest    = str[(comma + 1)..].strip
          ["var #{default} = #{ref};", bindings(rest, ref)].reject(&:empty?).join(" ")
        else
          "var #{str} = #{ref};"
        end
      end

      def named_imports(inner, ref)
        parse_list(inner).map { |orig, local| "var #{local} = #{ref}.#{orig};" }.join(" ")
      end

      def export_list(inner, ref)
        parse_list(inner).map do |orig, local|
          source = ref ? "#{ref}.#{orig}" : orig.to_s
          "__exports.#{local} = #{source};"
        end.join(" ")
      end

      def parse_list(inner)
        inner.to_s.split(",").map(&:strip).reject(&:empty?).map do |entry|
          if entry.include?(" as ")
            orig, local = entry.split(/\s+as\s+/).map(&:strip)
            [orig, local]
          elsif entry.include?(":")
            orig, local = entry.split(":").map(&:strip)
            [orig, local]
          else
            [entry, entry]
          end
        end
      end

      def reference(spec, current, base)
        "__require__(#{js_string(module_id(resolve_import(spec, current), base))})"
      end

      def relative_specifiers(source)
        specs = []

        source.each_line do |line|
          if (m = line.match(/\bfrom\s+['"]([^'"]+)['"]/))
            specs << m[1] if relative?(m[1])
          end
          if (m = line.match(/\A[ \t]*import\s+['"]([^'"]+)['"]/))
            specs << m[1] if relative?(m[1])
          end
        end

        specs
      end

      def relative?(spec)
        spec.start_with?(".")
      end

      def resolve_import(spec, current)
        target = ::File.expand_path(spec, ::File.dirname(current))
        found  = [target, "#{target}.js", ::File.join(target, "index.js")].find { |c| ::File.file?(c) }
        raise MissingImport, "Cannot resolve '#{spec}' from #{current}" unless found

        found
      end

      def module_id(path, base)
        Pathname.new(::File.expand_path(path))
                .relative_path_from(Pathname.new(base))
                .to_s
      rescue ArgumentError
        path
      end

      def js_string(str)
        JSON.generate(str)
      end

      def split_segments(js)
        segments = []
        buffer   = +""
        i        = 0

        while i < js.length
          ch = js[i]

          case ch
          when '"', "'", "`"
            segments << [:code, buffer] unless buffer.empty?
            buffer = +""
            str, i = read_string(js, i)
            segments << [:string, str]
          when "/"
            if js[i + 1] == "/"
              i = js.index("\n", i) || js.length
            elsif js[i + 1] == "*"
              stop = js.index("*/", i + 2) || (js.length - 2)
              i = stop + 2
            else
              buffer << ch
              i += 1
            end
          else
            buffer << ch
            i += 1
          end
        end

        segments << [:code, buffer] unless buffer.empty?
        segments
      end

      def read_string(js, i)
        quote = js[i]
        out   = quote.dup
        i    += 1

        while i < js.length
          ch = js[i]
          out << ch

          if ch == "\\"
            out << js[i + 1].to_s
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

      def minify_code(code)
        code.gsub(/\s+/, " ")
            .gsub(/\s*([{}();,:])\s*/) { ::Regexp.last_match(1) }
            .strip
      end
    end
  end
end
