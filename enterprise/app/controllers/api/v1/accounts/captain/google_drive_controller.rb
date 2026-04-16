class Api::V1::Accounts::Captain::GoogleDriveController < Api::V1::Accounts::BaseController
  include GoogleConcern

  before_action :check_admin_authorization
  before_action :set_hook, only: [:show, :destroy, :sync]

  def show
    return render json: { connected: false } unless @hook

    render json: {
      connected: true,
      folder_id: @hook.settings['folder_id'],
      assistant_id: @hook.settings['assistant_id'],
      last_synced_at: @hook.settings['last_synced_at'],
      sync_interval_hours: @hook.settings['sync_interval_hours'] || 6
    }
  end

  def create
    redirect_url = google_client.auth_code.authorize_url(
      redirect_uri: "#{base_url}/google/drive/callback",
      scope: 'https://www.googleapis.com/auth/drive.readonly',
      response_type: 'code',
      prompt: 'consent',
      access_type: 'offline',
      state: build_state,
      client_id: GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil)
    )

    render json: { success: true, url: redirect_url }
  end

  def destroy
    @hook&.destroy
    render json: { success: true }
  end

  def sync
    return render json: { error: 'Google Drive not connected' }, status: :not_found unless @hook

    Captain::GoogleDrive::SyncJob.perform_later(@hook)
    render json: { success: true, message: 'Sync started' }
  end

  private

  def check_admin_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end

  def set_hook
    @hook = Current.account.hooks.find_by(app_id: 'google_drive')
  end

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end

  def build_state
    {
      account_sgid: Current.account.to_sgid(expires_in: 15.minutes).to_s,
      assistant_id: params[:assistant_id],
      folder_id: params[:folder_id]
    }.to_json
  end
end
