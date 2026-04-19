module WhatsappBridge
  # Thin HTTP wrapper around one regional framework. Every interaction with
  # a WhatsApp bridge deployment — legacy or regional — flows through this
  # class, so URL/key lookup, header building, JSON handling and error
  # scrubbing happen in exactly one place.
  #
  # Usage:
  #   client = WhatsappBridge::RegionalClient.new('uk-west')
  #   client.get('/api/proxy/pool')
  #   client.post('/api/instances', name: 'foo', webhookUrl: '...')
  #   client.delete("/api/instances/#{id}")
  #
  # The low-level methods return whatever the framework returned as parsed
  # JSON (or `{'error' => '...'}` on transport/parse failure) — mirroring
  # the shape of the old `framework_request` helper so callers upgrade
  # incrementally.
  class RegionalClient
    DEFAULT_TIMEOUT = 10

    attr_reader :region

    def initialize(region_code)
      @region = WhatsappBridge::RegionRegistry.for(region_code)
      @region_code = region_code.to_s
    end

    # Returns true when this client can actually reach the framework.
    def configured?
      region&.configured?
    end

    def get(path, **opts)
      request(:get, path, nil, opts[:timeout] || DEFAULT_TIMEOUT)
    end

    # Accepts either `post(path, { k: v })` or inline `post(path, k: v)` —
    # both collapse to a plain hash body so callers don't have to think
    # about positional-vs-keyword collisions with the `timeout:` kwarg.
    def post(path, body = nil, **opts)
      request(:post, path, coerce_body(body, opts), opts[:timeout] || DEFAULT_TIMEOUT)
    end

    def put(path, body = nil, **opts)
      request(:put, path, coerce_body(body, opts), opts[:timeout] || DEFAULT_TIMEOUT)
    end

    def delete(path, **opts)
      request(:delete, path, nil, opts[:timeout] || DEFAULT_TIMEOUT)
    end

    private

    def coerce_body(body, opts)
      return body if body.is_a?(Hash)
      return body if body.nil? && opts.except(:timeout).empty?

      # Treat remaining keyword args as the body hash (minus :timeout).
      remaining = opts.except(:timeout)
      if body.nil?
        remaining
      elsif remaining.empty?
        body
      else
        (body || {}).merge(remaining)
      end
    end

    def request(method, path, body, timeout)
      return not_configured_error unless configured?

      options = { headers: headers, timeout: timeout }
      options[:body] = body.to_json if body.present?

      response = HTTParty.send(method, "#{region.url}#{path}", options)
      parse_body(response)
    rescue StandardError => e
      # Never log the API key. Include region code + path + error class only.
      Rails.logger.warn("[WhatsappBridge] #{@region_code} #{method.upcase} #{path} failed: #{e.class}")
      { 'error' => e.message }
    end

    def headers
      h = { 'Content-Type' => 'application/json' }
      h['X-API-Key'] = region.api_key if region&.api_key.present?
      h
    end

    def parse_body(response)
      return {} if response.body.blank?

      JSON.parse(response.body)
    rescue JSON::ParserError
      { 'error' => "Invalid JSON from #{@region_code}" }
    end

    def not_configured_error
      { 'error' => "WhatsApp region '#{@region_code}' is not configured." }
    end
  end
end
