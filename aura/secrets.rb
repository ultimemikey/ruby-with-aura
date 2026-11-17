module Aura

  module Secrets

    class MissingSecret < StandardError; end

    module_function

    def get(key, default = nil)
      value = ::ENV[key.to_s]
      value.nil? || value.empty? ? default : value
    end

    def require!(key)
      value = ::ENV[key.to_s]
      raise MissingSecret, "missing secret: #{key}" if value.nil? || value.empty?

      value
    end

    def fetch(key, *default)
      ::ENV.fetch(key.to_s, *default)
    end

    def load_dotenv(path = ".env", overwrite: false)
      file = path.to_s
      return 0 unless ::File.file?(file)

      loaded = 0
      ::File.foreach(file, encoding: "utf-8") do |line|
        entry = parse_line(line)
        next unless entry

        key, value = entry
        next if !overwrite && ::ENV.key?(key)

        ::ENV[key] = value
        loaded += 1
      end
      loaded
    end

    def parse_line(line)
      text = line.to_s.strip
      return nil if text.empty? || text.start_with?("#")

      text = text.sub(/\Aexport\s+/, "")
      key, value = text.split("=", 2)
      return nil if value.nil?

      key = key.strip
      return nil unless key.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)

      [key, unquote(value.strip)]
    end

    def unquote(value)
      return value[1..-2] if value.length >= 2 &&
                             ((value.start_with?('"') && value.end_with?('"')) ||
                              (value.start_with?("'") && value.end_with?("'")))

      value
    end
  end
end
