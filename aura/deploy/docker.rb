require "fileutils"
require "shellwords"

module Aura
  module Deploy

    module Docker
      DEFAULT_PORT        = 3000
      DEFAULT_RUBY        = "3.3"
      DEFAULT_START       = "bundle exec rackup -p %<port>s"
      DEFAULT_HEALTH_PATH = "/_aura/health"

      def self.dockerfile(config = nil, port: nil, ruby_version: nil, entrypoint: nil)
        port = resolve_port(config, port)
        ruby = ruby_version || DEFAULT_RUBY
        cmd  = resolve_start(config, port, entrypoint)

        <<~DOCKERFILE
          # syntax=docker/dockerfile:1
          # ---- Build stage ----
          FROM ruby:#{ruby}-slim AS build
          ENV BUNDLE_WITHOUT=development:test BUNDLE_PATH=/usr/local/bundle
          WORKDIR /app
          RUN apt-get update -qq && apt-get install -y --no-install-recommends build-essential git && rm -rf /var/lib/apt/lists/*
          COPY Gemfile Gemfile.lock ./
          RUN bundle install --jobs 4 --retry 3
          COPY . .

          # ---- Runtime stage ----
          FROM ruby:#{ruby}-slim AS runtime
          ENV RACK_ENV=production BUNDLE_WITHOUT=development:test BUNDLE_PATH=/usr/local/bundle BUNDLE_DEPLOYMENT=true PORT=#{port}
          WORKDIR /app
          RUN apt-get update -qq && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
          COPY --from=build /usr/local/bundle /usr/local/bundle
          COPY --from=build /app /app
          EXPOSE #{port}
          HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD curl -fsS http://localhost:#{port}#{DEFAULT_HEALTH_PATH} || exit 1
          #{cmd_line(cmd, port)}
        DOCKERFILE
      end

      def self.dockerignore
        <<~IGNORE
          .git
          .github
          .gitignore
          .gitattributes
          tmp
          log
          logs
          dist
          coverage
          node_modules
          .env
          .env.*
          *.log
          .DS_Store
          test
          spec
          docs
          README.md
        IGNORE
      end

      def self.compose(config = nil, port: nil)
        port = resolve_port(config, port)

        <<~YAML
          services:
            web:
              build: .
              ports:
                - "#{port}:#{port}"
              environment:
                RACK_ENV: production
                PORT: "#{port}"
              restart: unless-stopped
              healthcheck:
                test: ["CMD", "curl", "-fsS", "http://localhost:#{port}#{DEFAULT_HEALTH_PATH}"]
                interval: 30s
                timeout: 5s
                retries: 3

            # Optional: only needed when the app uses Redis-backed features.
            redis:
              image: redis:7-alpine
              restart: unless-stopped
              volumes:
                - redis-data:/data

          volumes:
            redis-data:
        YAML
      end

      def self.write!(dir = ".", config: nil, port: nil)
        FileUtils.mkdir_p(dir)

        files = {
          "Dockerfile"         => dockerfile(config, port: port),
          ".dockerignore"      => dockerignore,
          "docker-compose.yml" => compose(config, port: port)
        }

        files.map do |name, content|
          path = File.join(dir, name)
          File.write(path, content, mode: "w", encoding: "utf-8")
          path
        end
      end

      def self.resolve_port(config, port)
        return port.to_i if port
        return config.port if config.respond_to?(:port)

        DEFAULT_PORT
      end

      def self.resolve_start(config, port, entrypoint)
        return entrypoint if entrypoint

        if config.respond_to?(:start_command) && (cmd = config.start_command)
          return cmd
        end

        format(DEFAULT_START, port: port)
      end

      def self.cmd_line(command, port)
        command = command.to_s.empty? ? format(DEFAULT_START, port: port) : command.to_s

        if command.include?("$") || command.match?(/[|&;<>]/)
          escaped = command.gsub("\\", "\\\\").gsub('"', "\\\"")
          %(CMD ["sh", "-c", "#{escaped}"])
        else
          tokens = Shellwords.split(command)
          %(CMD [#{tokens.map { |t| %("#{t}") }.join(', ')}])
        end
      end
    end
  end
end
