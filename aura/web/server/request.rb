require "rack"
require "rack/multipart"
require "json"
require "uri"
require "ipaddr"

module Aura
  module Web
    module Server
      class Request
        MAX_FORWARDED_FOR_HOPS = 32

        attr_reader :rack_req

        def initialize(env, trusted_proxies: [])
          @env = env
          @rack_req = Rack::Request.new(env)
          @trusted_proxies = Array(trusted_proxies)
        end

        def headers
          @env
        end

        def header(name)
          @env["HTTP_#{name.to_s.upcase.tr('-', '_')}"]
        end

        def ip
          remote = @env["REMOTE_ADDR"] || "unknown"
          remote_ip = parse_ip(remote)
          return remote unless remote_ip && trusted_proxy?(remote_ip)

          forwarded = @env["HTTP_X_FORWARDED_FOR"].to_s
          return remote if forwarded.empty?

          forwarded_addresses = forwarded.split(",", -1)
          return remote if forwarded_addresses.empty? || forwarded_addresses.length > MAX_FORWARDED_FOR_HOPS

          chain = forwarded_addresses.map { |address| parse_ip(address.strip) }
          return remote if chain.any?(&:nil?)

          chain.reverse.find { |address| !trusted_proxy?(address) }&.to_s || remote
        end

        def path
          @rack_req.path_info
        end

        def query
          @query ||= begin
            qs = @env["QUERY_STRING"].to_s
            qs.empty? ? {} : ::URI.decode_www_form(qs).each_with_object({}) { |(k, v), acc| acc[k] = v }
          rescue ::StandardError
            {}
          end
        end

        def fragment
          value = header("x-aura-fragment")
          value.nil? || value.empty? ? nil : value
        end

        def method
          @rack_req.request_method
        end

        def params
          @params ||= normalize_uploads(rack_params)
        end

        def content_type
          @rack_req.media_type.to_s.downcase
        end

        def json_request?
          content_type == "application/json" || content_type.end_with?("+json")
        end

        def form_params
          return {} unless @rack_req.post? || @rack_req.put? || @rack_req.patch?

          normalize_uploads(@rack_req.POST)
        rescue StandardError
          {}
        end

        def session
          @rack_req.session || {}
        end

        def cookies
          @rack_req.cookies || {}
        end

        def json_body
          @json_body ||= begin
            body = @rack_req.body.read
            @rack_req.body.rewind
            body.empty? ? {} : JSON.parse(body, symbolize_names: true)
          rescue
            {}
          end
        end

        private

        def parse_ip(value)
          ::IPAddr.new(value)
        rescue ::IPAddr::InvalidAddressError
          nil
        end

        def trusted_proxy?(address)
          @trusted_proxies.any? { |network| network.include?(address) }
        end

        def rack_params
          @rack_req.params
        rescue StandardError
          begin
            @rack_req.GET
          rescue StandardError
            {}
          end
        end

        def normalize_uploads(params)
          return params unless params.is_a?(::Hash)

          params.each_with_object({}) do |(key, value), out|
            out[key] = normalize_upload_value(value) || value
          end
        end

        def normalize_upload_value(value)
          if value.respond_to?(:tempfile) && value.respond_to?(:original_filename)
            build_upload_hash(
              filename: value.original_filename,
              type: (value.content_type if value.respond_to?(:content_type)),
              tempfile: value.tempfile
            )
          elsif value.is_a?(::Hash) && (value[:tempfile] || value["tempfile"])
            build_upload_hash(
              filename: value[:filename] || value["filename"],
              type: value[:type] || value["type"],
              tempfile: value[:tempfile] || value["tempfile"]
            )
          end
        end

        def build_upload_hash(filename:, type:, tempfile:)
          {
            filename: filename,
            type: type,
            tempfile: tempfile,
            size: tempfile.respond_to?(:size) ? tempfile.size : nil
          }
        end
      end
    end
  end
end
