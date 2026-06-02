# frozen_string_literal: true

require "webrick"
require "rack"
require "stringio"
require "json"
require_relative "request_log"
require_relative "handler_context"

module HttpDecoy
  # A real WEBrick HTTP server that runs in a background thread.
  #
  # Uses WEBrick directly (no Rack::Handler) so it works with both
  # Rack 2.x and Rack 3.x without the rackup gem.
  #
  # Port 0 lets the OS pick a free port atomically — parallel test
  # runners never collide.
  class Server
    attr_reader :route_map, :request_log, :port

    def initialize(route_map)
      @route_map   = route_map
      @request_log = RequestLog.new
      @webrick     = nil
      @thread      = nil
      @port        = nil
      @scenario    = nil
      @scenario_mu = Mutex.new
    end

    def start
      rack_app = build_rack_app

      # WEBrick binds to the OS-assigned port during initialization.
      @webrick = WEBrick::HTTPServer.new(
        Port: 0,
        Logger: WEBrick::Log.new(File::NULL),
        AccessLog: []
      )
      @port = @webrick.config[:Port]

      @webrick.mount_proc("/") do |req, res|
        status, headers, body = rack_app.call(rack_env_from(req))
        res.status = status.to_i
        headers.each { |k, v| res[k] = v }
        res.body = Array(body).join
      rescue StandardError => e
        res.status = 500
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(error: "#{e.class}: #{e.message}")
      end

      @thread = Thread.new { @webrick.start }
      @thread.abort_on_exception = true

      # Poll until WEBrick enters its accept loop.
      deadline = Time.now + 5
      sleep(0.005) until @webrick.status == :Running || Time.now > deadline
      raise "http_decoy: server failed to start within 5 seconds" unless @webrick.status == :Running

      self
    end

    def stop
      @webrick&.shutdown
      @thread&.join(3)
      @thread  = nil
      @webrick = nil
    end

    def base_url = "http://127.0.0.1:#{@port}"

    # The Rack app is also exposed for WebMock's to_rack() interception.
    def rack_app
      @rack_app ||= build_rack_app
    end

    def with_scenario(name)
      @scenario_mu.synchronize { @scenario = name }
      yield
    ensure
      @scenario_mu.synchronize { @scenario = nil }
    end

    def current_scenario
      @scenario_mu.synchronize { @scenario }
    end

    private

    def build_rack_app
      route_map   = @route_map
      request_log = @request_log
      server      = self

      lambda do |env|
        req      = Rack::Request.new(env)
        method   = req.request_method
        path     = req.path_info
        scenario = server.current_scenario

        result   = route_map.router.match(method, path, scenario: scenario)
        result ||= route_map.router.match(method, path, scenario: nil) if scenario

        return json_response(404, error: "No route matches #{method} #{path}") unless result

        call_index = request_log.for(method, path).count
        ctx        = HandlerContext.new(req, result.params, call_index: call_index)

        begin
          ctx.instance_eval(&result.route.handler_block)
        rescue HandlerContext::ContractError => e
          return json_response(422, error: e.message)
        end

        request_log.record(
          method: method,
          path: path,
          body: ctx.body,
          headers: env.select { |k, _| k.start_with?("HTTP_") },
          query_params: ctx.query_params
        )

        ctx.response || json_response(200, status: "ok")
      end
    end

    # Convert a WEBrick::HTTPRequest into a Rack-compatible env hash.
    # Uses req.header (a Hash with lowercase keys) rather than each_header,
    # which does not exist on WEBrick::HTTPRequest.
    def rack_env_from(req)
      body_str = req.body || ""

      env = {
        "REQUEST_METHOD" => req.request_method,
        "SCRIPT_NAME" => "",
        "PATH_INFO" => req.path,
        "QUERY_STRING" => req.query_string || "",
        "SERVER_NAME" => "127.0.0.1",
        "SERVER_PORT" => @port.to_s,
        "CONTENT_TYPE" => req.content_type || "",
        "CONTENT_LENGTH" => body_str.bytesize.to_s,
        "rack.input" => StringIO.new(body_str),
        "rack.errors" => $stderr,
        "rack.multithread" => true,
        "rack.multiprocess" => false,
        "rack.run_once" => false,
        "rack.url_scheme" => "http"
      }

      # req.header is a Hash of { "lowercase-name" => ["value"] }
      req.header.each do |key, values|
        rack_key = key.upcase.tr("-", "_")
        next if %w[CONTENT_TYPE CONTENT_LENGTH].include?(rack_key)

        env["HTTP_#{rack_key}"] = Array(values).join(", ")
      end

      env
    end

    def json_response(status, payload)
      [status.to_i, { "Content-Type" => "application/json" }, [JSON.generate(payload)]]
    end
  end
end
