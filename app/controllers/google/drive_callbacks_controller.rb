class Google::DriveCallbacksController < ApplicationController
  include GoogleConcern

  def show
    state = JSON.parse(params[:state])
    @account = GlobalID::Locator.locate_signed(state['account_sgid'])
    raise 'Invalid or expired state' if @account.nil?

    token_response = google_client.auth_code.get_token(
      params[:code],
      redirect_uri: "#{base_url}/google/drive/callback"
    )

    hook = @account.hooks.find_or_initialize_by(app_id: 'google_drive')
    hook.update!(
      status: 'enabled',
      access_token: token_response.token,
      settings: {
        'refresh_token' => token_response.refresh_token || hook.settings&.dig('refresh_token'),
        'expires_at' => token_response.expires_at,
        'assistant_id' => state['assistant_id'],
        'folder_id' => state['folder_id'].presence,
        'sync_interval_hours' => 6
      }
    )

    redirect_to documents_redirect_url(state['assistant_id'])
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    redirect_to '/'
  end

  private

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end

  def documents_redirect_url(assistant_id)
    if assistant_id.present?
      "/app/accounts/#{@account.id}/captain/#{assistant_id}/documents?google_drive=connected"
    else
      "/app/accounts/#{@account.id}/captain/documents?google_drive=connected"
    end
  end
end
