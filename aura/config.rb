require "json"

module Aura

  class Config
    DEFAULT_FILENAME = "aura.config.json"
    DEFAULT_PORT     = 3000

    attr_reader :root, :data, :path

    def self.load(root = Dir.pwd, path: nil)
      new(root, path)
    end

    def initialize(root = Dir.pwd, path = nil)
      @root = root
      @path = path || File.join(root, DEFAULT_FILENAME)
      @data = File.file?(@path) ? JSON.parse(File.read(@path, encoding: "utf-8")) : {}
    rescue JSON::ParserError => e
      raise ArgumentError, "Invalid JSON configuration at #{@path}: #{e.message}"
    end

    def name
      data.dig("framework", "name") || "aura"
    end

    def runtime
      data.dig("framework", "runtime") || "rack"
    end

    def server_entry
      data.dig("entrypoints", "server") || "config.ru"
    end

    def server_entry_path
      File.join(root, server_entry)
    end

    def static_paths
      data.dig("staticAssets", "paths") || ["public"]
    end

    def env_defaults
      data["env"] || {}
    end

    def supports_sse?
      !!data.dig("platformFlags", "supportsSSE")
    end

    def port
      (ENV["PORT"] || env_defaults["PORT"] || DEFAULT_PORT).to_i
    end

    def host
      ENV["HOST"] || env_defaults["HOST"] || "0.0.0.0"
    end

    def build_command
      data.dig("buildCommandTemplate", "default") || "bundle install"
    end

    def start_command
      data.dig("startCommandTemplate", "default")
    end

    def environment
      ENV.fetch("AURA_ENV") { ENV.fetch("RACK_ENV", env_defaults["RACK_ENV"] || "development") }
    end
  end
end
