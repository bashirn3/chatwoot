class Api::V1::Accounts::TypebotsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :ensure_typebot_configured
  before_action :ensure_workspace, only: [:index, :create]

  def index
    bots = typebot_request(:get, "/api/v1/typebots", params: { workspaceId: workspace_id })
    if bots.nil?
      return render json: {
        error: typebot_last_error_message,
        typebots: []
      }, status: :bad_gateway
    end

    list = extract_typebots_list(bots)
    render json: { typebots: list }
  end

  def create
    body = { workspaceId: workspace_id, typebot: { name: creation_name } }
    result = typebot_request(:post, '/api/v1/typebots', body: body)
    if result.nil?
      return render json: {
        error: typebot_last_error_message
      }, status: :bad_gateway
    end

    typebot = extract_typebot(result)
    if typebot.blank?
      return render json: {
        error: 'Typebot returned no bot payload. Check server logs for the Typebot API response.'
      }, status: :unprocessable_entity
    end

    render json: {
      typebot: typebot,
      editor_url: editor_redirect_url(typebot['id'] || typebot[:id])
    }
  end

  def show
    result = typebot_request(:get, "/api/v1/typebots/#{params[:id]}")
    render json: { typebot: extract_typebot(result) }
  end

  def destroy
    typebot_request(:delete, "/api/v1/typebots/#{params[:id]}")
    render json: { success: true }
  end

  def publish
    typebot_request(:post, "/api/v1/typebots/#{params[:id]}/publish")
    render json: { success: true }
  end

  def editor
    typebot_id = params[:id]
    token = provision_typebot_session
    return render json: { error: 'Failed to create Typebot session' }, status: :unprocessable_entity unless token

    builder = typebot_builder_url.to_s.chomp('/')
    redirect_path = "/typebots/#{typebot_id}/edit"
    open_url = "#{builder}/chatwoot-auth?token=#{token}&redirect=#{redirect_path}"

    render json: {
      redirect_url: "#{builder}#{redirect_path}",
      session_token: token,
      open_url: open_url,
      builder_base_url: builder
    }
  end

  def assign
    typebot_data = typebot_request(:get, "/api/v1/typebots/#{params[:id]}")
    typebot = extract_typebot(typebot_data)
    return render json: { error: 'Bot not found' }, status: :not_found unless typebot

    typebot_request(:post, "/api/v1/typebots/#{params[:id]}/publish") unless typebot_data&.dig('publishedTypebot')

    public_id = typebot['publicId']
    return render json: { error: 'Bot has no public ID. Set one in the Typebot editor Share tab.' }, status: :unprocessable_entity if public_id.blank?

    inbox = Current.account.inboxes.find(params[:inbox_id])
    hook = Current.account.hooks.find_or_initialize_by(app_id: 'router', inbox_id: inbox.id)
    hook.update!(
      status: 'enabled',
      settings: {
        'typebot_url' => typebot_viewer_internal_url,
        'public_id' => public_id,
        'router_mode' => 'typebot_only'
      }
    )

    render json: { success: true, hook_id: hook.id, inbox_id: inbox.id }
  end

  def unassign
    inbox = Current.account.inboxes.find(params[:inbox_id])
    hook = Current.account.hooks.find_by(app_id: 'router', inbox_id: inbox.id)
    hook&.destroy
    render json: { success: true }
  end

  def toggle_bot
    conversation = Current.account.conversations.find(params[:conversation_id])
    paused = conversation.additional_attributes&.dig('bot_paused')
    attrs = conversation.additional_attributes || {}
    attrs['bot_paused'] = !paused
    attrs.delete('typebot_session_id') unless attrs['bot_paused']
    conversation.update!(additional_attributes: attrs)

    render json: { success: true, bot_paused: attrs['bot_paused'], conversation_id: conversation.display_id }
  end

  private

  def typebot_builder_url
    @typebot_builder_url ||= ENV.fetch('TYPEBOT_BUILDER_URL', 'http://localhost:3001')
  end

  def typebot_builder_internal_url
    @typebot_builder_internal_url ||= ENV.fetch('TYPEBOT_BUILDER_INTERNAL_URL', 'http://typebot-builder:3000')
  end

  def typebot_viewer_internal_url
    @typebot_viewer_internal_url ||= ENV.fetch('TYPEBOT_VIEWER_INTERNAL_URL',
                                               ENV.fetch('TYPEBOT_VIEWER_URL', 'http://localhost:3002'))
  end

  def typebot_api_token
    @typebot_api_token ||= ENV.fetch('TYPEBOT_API_TOKEN', nil)
  end

  def typebot_admin_email
    ENV.fetch('TYPEBOT_ADMIN_EMAIL', 'admin@wasup.co')
  end

  def ensure_typebot_configured
    return if typebot_builder_url.present? && typebot_api_token.present?

    render json: { error: 'Typebot is not configured. Set TYPEBOT_BUILDER_URL and TYPEBOT_API_TOKEN (create the token in Typebot: Settings → My account → API tokens).' }, status: :service_unavailable
  end

  def workspace_id
    Current.account.custom_attributes&.dig('typebot_workspace_id')
  end

  def ensure_workspace
    return if workspace_id.present?

    result = typebot_request(:post, '/api/v1/workspaces', body: { name: "Account #{Current.account.id} - #{Current.account.name}" })
    ws_id = result&.dig('workspace', 'id') || result&.dig('data', 'workspace', 'id')

    if ws_id.present?
      attrs = Current.account.custom_attributes || {}
      attrs['typebot_workspace_id'] = ws_id
      Current.account.update!(custom_attributes: attrs)
    else
      render json: { error: "Failed to provision Typebot workspace. #{typebot_last_error_message}" }, status: :unprocessable_entity
    end
  end

  def editor_redirect_url(typebot_id)
    return nil unless typebot_id

    "/api/v1/accounts/#{Current.account.id}/typebots/#{typebot_id}/editor"
  end

  def provision_typebot_session
    db_url = typebot_db_url
    return nil unless db_url

    token = SecureRandom.hex(32)
    session_id = "sess_cw_#{SecureRandom.hex(8)}"

    conn = PG.connect(db_url)
    admin = conn.exec_params('SELECT id FROM "User" WHERE email = $1 LIMIT 1', [typebot_admin_email])
    return nil if admin.ntuples.zero?

    user_id = admin.getvalue(0, 0)
    conn.exec_params(
      'INSERT INTO "Session" (id, "sessionToken", "userId", expires) VALUES ($1, $2, $3, $4)',
      [session_id, token, user_id, (Time.current + 1.year).utc.strftime('%Y-%m-%d %H:%M:%S')]
    )
    conn.close
    token
  rescue StandardError => e
    Rails.logger.error "Typebot session creation failed: #{e.message}"
    nil
  end

  def typebot_db_url
    pg_pass = ENV.fetch('POSTGRES_PASSWORD', 'wasup-pg-secret-2026')
    pg_host = ENV.fetch('POSTGRES_HOST', 'postgres')
    "postgresql://postgres:#{pg_pass}@#{pg_host}:5432/typebot"
  end

  def creation_name
    params[:name].presence || 'Untitled Bot'
  end

  def extract_typebots_list(payload)
    return [] unless payload.is_a?(Hash)

    payload['typebots'] || payload['data']&.dig('typebots') || []
  end

  def extract_typebot(payload)
    return nil unless payload.is_a?(Hash)

    payload['typebot'] || payload['data']&.dig('typebot')
  end

  def typebot_last_error_message
    msg = @typebot_last_error_body.to_s.presence
    return 'Typebot API request failed (no response body).' if msg.blank?

    parsed = JSON.parse(msg)
    parsed['message'] || parsed['error'] || msg
  rescue JSON::ParserError
    msg.truncate(300)
  end

  def typebot_request(method, path, body: nil, params: nil)
    url = "#{typebot_builder_internal_url}/api#{path.start_with?('/api') ? path.sub('/api', '') : path}"
    headers = { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{typebot_api_token}" }
    options = { headers: headers, timeout: 15 }
    options[:body] = body.to_json if body.present?
    options[:query] = params if params.present?

    @typebot_last_error_body = nil
    response = HTTParty.send(method, url, options)
    unless response.success?
      @typebot_last_error_body = response.body
      Rails.logger.warn(
        "[Typebot API] #{method.to_s.upcase} #{url} => #{response.code}: #{response.body&.truncate(800)}"
      )
      return nil
    end

    response.parsed_response
  rescue StandardError => e
    @typebot_last_error_body = e.message
    Rails.logger.error "Typebot API error: #{e.message}"
    nil
  end
end
