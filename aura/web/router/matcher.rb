require "uri"

module Aura
  module Web
    module Router
      class Matcher

        def self.match(pattern, path)
          path_only, = split(path)

          pat_parts = pattern.to_s.split("/").reject(&:empty?)
          path_parts = path_only.split("/").reject(&:empty?)

          return nil if pat_parts.size != path_parts.size

          params = {}
          pat_parts.each_with_index do |part, idx|
            if part.start_with?(":")
              name = part[1..-1].to_sym
              params[name] = path_parts[idx]
            elsif part != path_parts[idx]
              return nil
            end
          end

          params
        end

        def self.split(path)
          str = path.to_s

          fragment = nil
          if (hash_index = str.index("#"))
            fragment = str[(hash_index + 1)..]
            str = str[0...hash_index]
          end

          query = {}
          if (query_index = str.index("?"))
            query = parse_query(str[(query_index + 1)..])
            str = str[0...query_index]
          end

          [str, query, fragment]
        end

        def self.parse_query(query_string)
          return {} if query_string.nil? || query_string.empty?

          ::URI.decode_www_form(query_string).each_with_object({}) do |(key, value), acc|
            acc[key] = value
          end
        rescue ::ArgumentError
          {}
        end
      end
    end
  end
end
