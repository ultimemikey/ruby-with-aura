require "digest"

module Aura
  module Assets

    module Fingerprint
      module_function

      def digest(content_or_path)
        content = read(content_or_path)
        Digest::SHA256.hexdigest(content)[0, 8]
      end

      def hashed_name(path)
        path = path.to_s
        ext  = ::File.extname(path)
        base = ext.empty? ? path : path[0, path.length - ext.length]
        "#{base}.#{digest(path)}#{ext}"
      end

      def read(content_or_path)
        if content_or_path.is_a?(::String) && ::File.file?(content_or_path)
          ::File.binread(content_or_path)
        else
          content_or_path.to_s
        end
      end
    end
  end
end
