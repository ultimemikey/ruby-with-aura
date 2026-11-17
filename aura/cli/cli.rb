require "fileutils"
require_relative "../aura"
require_relative "../config"

module Aura

  module CLI
    class Error < StandardError; end

    module Templates
      PAGE = <<~'RUBY'
        use aura from ".aura"

        title "%<title>s"

        render do
          body do
            div class: "page" do
              h1 "%<title>s"
            end
          end
        end
      RUBY

      COMPONENT = <<~'RUBY'
        use aura from ".aura"

        # <%%= %<sym>s %%>   — use this component from any page
        define :%<sym>s do
          div class: "%<class_name>s" do
            text "TODO: %<title>s"
          end
        end
      RUBY

      INCLUDE = <<~'RUBY'
        # Fragment included with: include "%<path>s"
        div class: "%<class_name>s" do
          text "TODO: %<title>s"
        end
      RUBY

      ROUTE = <<~'RUBY'
        # API route handled by the Aura server router: %<path>s
        get  { json(ok: true) }
      RUBY
    end

    def self.generate(root, type, name)
      raise Error, "missing name" if name.nil? || name.to_s.empty?

      segments = name.to_s.split("/")
      unless segments.all? { |s| s.match?(/\A[a-zA-Z0-9_-]+\z/) }
        raise Error, "invalid name #{name.inspect} (use letters, digits, _ - and /)"
      end

      relative, body =
        case type.to_s
        when "page"      then ["app/pages/#{name}.rb",      page_body(name)]
        when "component" then ["app/components/#{name}.rb", component_body(name)]
        when "include"   then ["app/includes/#{name}.rb",   include_body(name)]
        when "route"     then ["app/api/#{name}.rb",        route_body(name)]
        else
          raise Error, "unknown generator #{type.inspect} (use page, component, include or route)"
        end

      target = File.join(root, relative)
      raise Error, "#{relative} already exists" if File.exist?(target)

      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, body, mode: "w", encoding: "utf-8")
      target
    end

    def self.page_body(name)
      format(Templates::PAGE, title: humanize(name))
    end

    def self.component_body(name)
      base = File.basename(name)
      format(Templates::COMPONENT, sym: base, title: humanize(name), class_name: base.tr("_", "-"))
    end

    def self.include_body(name)
      base = File.basename(name)
      format(Templates::INCLUDE, path: name, title: humanize(name), class_name: base.tr("_", "-"))
    end

    def self.route_body(name)
      format(Templates::ROUTE, path: "/api/#{name}")
    end

    def self.humanize(name)
      File.basename(name).split(/[-_]/).map(&:capitalize).join(" ")
    end

    def self.run(argv)
      command = argv.shift

      case command
      when "dev"                  then dev(argv)
      when "build"                then build(argv)
      when "export"               then export(argv)
      when "analyze"              then analyze(argv)
      when "generate", "g"        then generate_command(argv)
      when "aura", nil            then serve
      when "version", "-v", "--version" then version
      when "help", "-h", "--help" then help
      else
        warn "Unknown command: #{command}"
        help
        1
      end
    end

    def self.dev(_argv = [])
      config = Aura::Config.load(Dir.pwd)
      puts " Aura dev server → http://localhost:#{config.port}"
      puts " Environment: #{config.environment}"
      start_server(config)
      0
    end

    def self.serve
      config = Aura::Config.load(Dir.pwd)
      puts " Starting Ruby with Aura Application Server..."
      puts " Open http://localhost:#{config.port}"
      start_server(config)
      0
    end

    def self.build(_argv = [], root: Dir.pwd)
      config = Aura::Config.load(root)
      command = config.build_command
      puts "> #{command}"
      system(command, chdir: config.root) ? 0 : 1
    end

    def self.export(argv, root: Dir.pwd)
      out = argv.shift || "dist"

      router = Web::Router::Router.new
      router.draw { files "app/pages" }

      written = SSG::Exporter.new(router: router, out: out, root: root).export

      puts "Exported #{written.size} route(s) to #{out}/"
      written.each { |f| puts "  #{f.sub(root + File::SEPARATOR, "")}" }
      0
    rescue => e
      warn "export: #{e.message}"
      1
    end

    def self.analyze(argv, out: nil)
      target = argv.shift || "dist"
      report = Assets::BundleAnalyzer.analyze(target, out: out)

      puts report.to_text
      puts
      puts "Total: #{report.total} bytes across #{report.count} file(s)"
      0
    rescue => e
      warn "analyze: #{e.message}"
      1
    end

    def self.generate_command(argv)
      type = argv.shift
      name = argv.shift
      path = generate(Dir.pwd, type, name)
      puts "created #{path.sub(Dir.pwd + File::SEPARATOR, "")}"
      0
    rescue Error => e
      warn "generate: #{e.message}"
      1
    end

    def self.help
      puts <<~TEXT
        Aura CLI

        Usage: ruby run <command>

        Commands:
          dev                 Start the development server
          build               Run the configured build command
          export [out]        Static-export every file route to dist/ (default)
          analyze [dir]       Report the bundle size of a build directory
          generate <type> <name>
                              Scaffold a page, component, include or route
          aura                Start the application server (legacy alias)
          version             Print the framework version
      TEXT
      0
    end

    def self.version
      puts "Aura #{Aura::VERSION}"
      0
    end

    def self.start_server(config)
      require "rackup"
      Rackup::Server.start(
        config: config.server_entry_path,
        Port:   config.port,
        Host:   config.host
      )
    rescue LoadError
      require "rack"
      Rack::Server.start(
        config: config.server_entry_path,
        Port:   config.port,
        Host:   config.host
      )
    end
  end
end
