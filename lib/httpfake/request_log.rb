# frozen_string_literal: true

module HttpFake
  # Thread-safe store of every request received by the fake server.
  # Cleared between examples via Server#stop → new Server per example.
  class RequestLog
    # Use http_method instead of method to avoid overriding Struct#method.
    Entry = Struct.new(:http_method, :path, :body, :headers, :query_params, keyword_init: true)

    def initialize
      @entries = []
      @mutex   = Mutex.new
    end

    def record(method:, path:, body:, headers:, query_params:)
      @mutex.synchronize do
        @entries << Entry.new(
          http_method: method.to_s.upcase,
          path: path,
          body: body,
          headers: headers,
          query_params: query_params
        )
      end
    end

    def all
      @mutex.synchronize { @entries.dup }
    end

    # Returns all entries matching the given HTTP method and exact path.
    def for(method, path)
      all.select { |e| e.http_method == method.to_s.upcase && e.path == path }
    end

    def clear
      @mutex.synchronize { @entries.clear }
    end

    def count
      @mutex.synchronize { @entries.size }
    end
  end
end
