require "fileutils"

module Aura
  module Assets

    module ImageOptimizer

      TOOLS = %w[sips magick convert].freeze

      module_function

      def available?
        !tool.nil?
      end

      def tool
        @tool ||= TOOLS.find { |command| which(command) }
      end

      def optimize(path, out_dir: "dist/images", max_width: nil, format: nil)
        src = path.to_s
        ::FileUtils.mkdir_p(out_dir)
        out = output_path(src, out_dir, format)

        unless tool
          ::FileUtils.cp(src, out)
          return { path: out, width: nil, copied: true }
        end

        convert(src, out, max_width)

        unless ::File.file?(out)
          ::FileUtils.cp(src, out)
          return { path: out, width: nil, copied: true }
        end

        { path: out, width: nil, copied: false }
      end

      def srcset(path, widths: [320, 640, 960])
        base = ::File.basename(path.to_s, ".*")

        widths.map { |w| "/images/#{base}-#{w}.webp #{w}w" }.join(", ")
      end

      def output_path(src, out_dir, format)
        ext = format && !format.to_s.empty? ? format.to_s : ::File.extname(src).sub(/\A\./, "")
        ext = "webp" if ext.empty?
        base = ::File.basename(src, ".*")
        ::File.join(out_dir, "#{base}.#{ext}")
      end

      def convert(src, out, max_width)
        args =
          case tool
          when "sips"
            list = ["sips"]
            list += ["-Z", max_width.to_s] if max_width
            list + [src, "--out", out]
          else
            list = [tool, src]
            list += ["-resize", "#{max_width}x"] if max_width
            list + [out]
          end

        system(*args, out: ::File::NULL, err: ::File::NULL)
      end

      def which(command)
        ::ENV.fetch("PATH", "").split(::File::PATH_SEPARATOR).any? do |dir|
          candidate = ::File.join(dir, command)
          ::File.file?(candidate) && ::File.executable?(candidate)
        end
      end
    end
  end
end
