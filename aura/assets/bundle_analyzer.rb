require "json"
require "fileutils"

module Aura
  module Assets

    class BundleAnalyzer
      UNITS = %w[B KB MB GB].freeze

      attr_reader :entries

      def self.analyze(entries, out: nil)
        analyzer = new(entries)
        analyzer.report
        analyzer.write(out) if out
        analyzer
      end

      def initialize(entries)
        @entries = entries
        @report  = nil
      end

      def report
        @report ||= build_report
      end

      def total
        report[:total]
      end

      def count
        report[:count]
      end

      def files
        report[:files]
      end

      def to_text
        width = files.map { |f| f[:size].length }.max || 0
        width = width < 8 ? 8 : width

        lines = files.map { |f| "#{f[:size].rjust(width)}  #{f[:path]}" }
        lines << "#{"-" * width}  #{"-" * 24}"
        lines << "#{human_size(total).rjust(width)}  TOTAL (#{count} file#{count == 1 ? '' : 's'})"
        lines.join("\n")
      end

      def to_json(*_args)
        JSON.pretty_generate(report)
      end

      def write(out)
        target = ::File.expand_path(out.to_s)
        ::FileUtils.mkdir_p(::File.dirname(target))
        body = target.end_with?(".json") ? to_json : to_text
        ::File.write(target, body, mode: "w", encoding: "utf-8")
        target
      end

      private

      def build_report
        entries = collect(@entries).map { |path| { path: path, bytes: ::File.size(path) } }
        entries.sort_by! { |entry| -entry[:bytes] }
        entries.each { |entry| entry[:size] = human_size(entry[:bytes]) }

        { total: entries.sum { |e| e[:bytes] }, count: entries.length, files: entries }
      end

      def collect(input)
        Array(input).flat_map { |item| expand(item) }
                     .select { |path| ::File.file?(path) }
                     .uniq
                     .sort
      end

      def expand(item)
        path = item.to_s
        ::File.directory?(path) ? ::Dir.glob(::File.join(path, "**", "*")) : [path]
      end

      def human_size(bytes)
        value = bytes.to_f
        index = 0
        while value >= 1024 && index < UNITS.length - 1
          value /= 1024
          index += 1
        end

        index.zero? ? "#{bytes} B" : format("%.1f %s", value, UNITS[index])
      end
    end
  end
end
