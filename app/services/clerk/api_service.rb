class Clerk::ApiService
  BASE_URL = 'https://api.clerk.com/v1'.freeze

  def initialize
    @secret_key = ENV.fetch('CLERK_SECRET_KEY', nil)
  end

  def verify_session_token(token)
    # Decode without verification first to get the issuer for JWKS URL
    unverified = decode_jwt_payload(token)
    return nil unless unverified

    issuer = unverified['iss']
    return nil unless issuer

    # Fetch JWKS and verify the JWT signature
    jwks_data = fetch_jwks(issuer)
    return nil unless jwks_data

    jwks = JWT::JWK::Set.new(jwks_data)
    payload, _header = JWT.decode(token, nil, true, algorithms: ['RS256'], jwks: jwks)

    # Return a hash that looks like a session response with user_id
    { 'user_id' => payload['sub'], 'org_id' => payload['org_id'], 'org_role' => payload['org_role'],
      'org_slug' => payload['org_slug'], 'id' => payload['sid'] }
  rescue JWT::DecodeError => e
    Rails.logger.error("Clerk JWT verification failed: #{e.message}")
    nil
  end

  def fetch_user(clerk_user_id)
    clerk_get("/users/#{clerk_user_id}")
  end

  def fetch_user_organization_memberships(clerk_user_id)
    response = clerk_get("/users/#{clerk_user_id}/organization_memberships")
    return [] unless response.is_a?(Hash) && response['data']

    response['data']
  end

  def fetch_organization(clerk_org_id)
    clerk_get("/organizations/#{clerk_org_id}")
  end

  private

  def fetch_jwks(issuer)
    uri = URI("#{issuer}/.well-known/jwks.json")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    response = http.request(Net::HTTP::Get.new(uri))

    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("Clerk JWKS fetch error: #{e.message}")
    nil
  end

  def decode_jwt_payload(token)
    parts = token.split('.')
    return nil unless parts.length == 3

    padding = '=' * ((4 - (parts[1].length % 4)) % 4)
    payload_json = Base64.urlsafe_decode64(parts[1] + padding)
    JSON.parse(payload_json)
  rescue StandardError
    nil
  end

  def clerk_get(path)
    uri = URI("#{BASE_URL}#{path}")
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@secret_key}"
    request['Content-Type'] = 'application/json'

    execute_request(uri, request)
  end

  def clerk_post(path, body)
    uri = URI("#{BASE_URL}#{path}")
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@secret_key}"
    request['Content-Type'] = 'application/json'
    request.body = body.to_json

    execute_request(uri, request)
  end

  def execute_request(uri, request)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    response = http.request(request)

    Rails.logger.info("Clerk API #{request.method} #{uri.path} -> #{response.code}: #{response.body.first(500)}")
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("Clerk API error: #{e.message}")
    nil
  end
end
