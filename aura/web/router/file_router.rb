require_relative "route"

module Aura
  module Web
    module Router

      class FileRouter

        DYNAMIC = /\A\[(\.\.\.)?([^\]]+)\](\.rb)?\z/

        GROUP = /\A\([^)]+\)\z/

        OPTIONAL_CATCH_ALL = /\A\[\[\.\.\.([^\]]+)\]\](\.rb)?\z/

        LAYOUT_FILE     = "layout.rb"
        ERROR_FILE      = "error.rb"
        LOADING_FILE    = "loading.rb"
        NOT_FOUND_FILE  = "not-found.rb"
        CONVENTION_FILES = [LAYOUT_FILE, ERROR_FILE, LOADING_FILE, NOT_FOUND_FILE].freeze

        attr_reader :root, :root_abs

        def initialize(root = "app/pages")
          @root = root
          @root_abs = ::File.expand_path(root)
        end

        def resolve(path)
          segments = normalize(path)
          return nil if segments.nil?

          match = walk(@root_abs, segments, 0, {})
          return nil unless match

          file, params = match
          rel = file.sub(@root_abs + ::File::SEPARATOR, "").sub(/\.rb\z/, "")
          [Route.new(path, "#{@root}/#{rel}"), params]
        end

        def layout_chain(page_file)
          ancestors(page_file).reverse.filter_map { |dir| existing(dir, LAYOUT_FILE) }
        end

        def error_file_for(page_file)
          ancestors(page_file).filter_map { |dir| existing(dir, ERROR_FILE) }.first
        end

        def loading_file_for(page_file)
          ancestors(page_file).filter_map { |dir| existing(dir, LOADING_FILE) }.first
        end

        def not_found_file
          existing(@root_abs, NOT_FOUND_FILE)
        end

        def static_pages
          prefix_len = @root_abs.length + 1

          ::Dir.glob(::File.join(@root_abs, "**", "*.rb")).sort.filter_map do |file|
            rel  = file[prefix_len..].to_s
            base = ::File.basename(rel)
            next if CONVENTION_FILES.include?(base)
            next if base.start_with?("_")
            next if rel.split("/").any? { |seg| seg.start_with?("[") }

            ["/#{url_for(rel)}", file]
          end
        end

        def static_routes
          static_pages.map(&:first)
        end

        private

        def url_for(rel)
          rel.split("/").reject { |seg| seg.match?(GROUP) }.join("/")
             .sub(/\.rb\z/, "").sub(%r{/index\z}, "").sub(/\Aindex\z/, "")
             .sub(%r{\A/+}, "").sub(%r{/+\z}, "")
        end

        def ancestors(page_file)
          return [] if page_file.nil?

          dir = ::File.dirname(page_file)
          return [] unless dir == @root_abs || dir.start_with?(@root_abs + ::File::SEPARATOR)

          chain = []
          current = dir
          loop do
            chain << current
            break if current == @root_abs

            parent = ::File.dirname(current)
            break if parent == current || !parent.start_with?(@root_abs)
            current = parent
          end
          chain
        end

        def existing(dir, filename)
          path = ::File.join(dir, filename)
          ::File.file?(path) ? path : nil
        end

        def normalize(path)
          raw = path.to_s.split("#", 2).first.to_s.split("?", 2).first.to_s
          stripped = raw.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
          return [] if stripped.empty?

          segments = stripped.split("/")
          return nil if segments.any? { |s| s.empty? || s == "." || s == ".." }

          segments
        end

        def walk(dir, segments, index, params)
          return nil unless ::File.directory?(dir)

          if index == segments.length
            index_file = ::File.join(dir, "index.rb")
            return [index_file, params] if ::File.file?(index_file)

            optional_catch_all_entries(dir).each do |entry|
              match = entry.match(OPTIONAL_CATCH_ALL)
              name = match[1].to_sym
              entry_path = ::File.join(dir, entry)

              if match[2]
                return [entry_path, params.merge(name => "")]
              else
                found = walk(entry_path, segments, segments.length, params.merge(name => ""))
                return found if found
              end
            end

            return nil
          end

          segment = segments[index]
          leaf = index == segments.length - 1

          if leaf
            literal = ::File.join(dir, "#{segment}.rb")
            return [literal, params] if ::File.file?(literal)
          end

          sub = ::File.join(dir, segment)
          if ::File.directory?(sub)
            found = walk(sub, segments, index + 1, params)
            return found if found
          end

          group_entries(dir).each do |entry|
            found = walk(::File.join(dir, entry), segments, index, params)
            return found if found
          end

          dynamic_entries(dir).each do |entry|
            match = entry.match(DYNAMIC)
            catch_all = !match[1].nil?
            name      = match[2].to_sym
            file      = !match[3].nil?
            entry_path = ::File.join(dir, entry)

            if catch_all
              value = segments[index..-1].join("/")
              merged = params.merge(name => value)
              if file
                return [entry_path, merged]
              else
                found = walk(entry_path, segments, segments.length, merged)
                return found if found
              end
            elsif file
              next unless leaf
              return [entry_path, params.merge(name => segment)]
            else
              found = walk(entry_path, segments, index + 1, params.merge(name => segment))
              return found if found
            end
          end

          optional_catch_all_entries(dir).each do |entry|
            match = entry.match(OPTIONAL_CATCH_ALL)
            name = match[1].to_sym
            entry_path = ::File.join(dir, entry)
            merged = params.merge(name => segments[index..-1].join("/"))

            if match[2]
              return [entry_path, merged]
            else
              found = walk(entry_path, segments, segments.length, merged)
              return found if found
            end
          end

          nil
        end

        def dynamic_entries(dir)
          ::Dir.children(dir).select { |e| e.match?(DYNAMIC) }.sort
        rescue SystemCallError
          []
        end

        def group_entries(dir)
          ::Dir.children(dir).select do |e|
            e.match?(GROUP) && ::File.directory?(::File.join(dir, e))
          end.sort
        rescue SystemCallError
          []
        end

        def optional_catch_all_entries(dir)
          ::Dir.children(dir).select { |e| e.match?(OPTIONAL_CATCH_ALL) }.sort
        rescue SystemCallError
          []
        end
      end
    end
  end
end
