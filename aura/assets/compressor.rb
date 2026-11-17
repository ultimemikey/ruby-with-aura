require "zlib"
require "stringio"
require "fileutils"

module Aura
  module Assets

    module Compressor

      TEXT_EXTENSIONS = %w[
        .css .js .mjs .html .htm .svg .json .txt .xml .map .webmanifest
      ].freeze

      SMALL_INPUT = 100

      module_function

      def gzip(data)
        io = StringIO.new(+"", "wb")
        writer = Zlib::GzipWriter.new(io)
        writer.write(data.to_s)
        writer.close
        io.string
      end

      def brotli(data)
        str = data.to_s
        return nil if str.bytesize < SMALL_INPUT
        return nil unless which("brotli")

        IO.popen(["brotli", "-c", "-q", "11"], "r+") do |io|
          io.write(str)
          io.close_write
          io.read
        end
      rescue StandardError
        nil
      end

      def compress_dir(dir)
        created = []

        ::Dir.glob(::File.join(dir, "**", "*")).sort.each do |file|
          next unless ::File.file?(file)
          next unless TEXT_EXTENSIONS.include?(::File.extname(file).downcase)

          target = "#{file}.gz"
          ::File.binwrite(target, gzip(::File.binread(file)))
          created << target
        end

        created
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
