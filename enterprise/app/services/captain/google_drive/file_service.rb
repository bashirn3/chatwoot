class Captain::GoogleDrive::FileService
  SUPPORTED_MIME_TYPES = [
    'application/pdf',
    'application/vnd.google-apps.document',
    'application/vnd.google-apps.spreadsheet',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/msword'
  ].freeze

  GOOGLE_NATIVE_TYPES = %w[
    application/vnd.google-apps.document
    application/vnd.google-apps.spreadsheet
  ].freeze

  def initialize(hook)
    @hook = hook
    @drive_service = build_drive_service
  end

  def list_files(folder_id: nil)
    refresh_token_if_needed!

    query_parts = [mime_type_query]
    query_parts << "'#{folder_id}' in parents" if folder_id.present?
    query_parts << "trashed = false"

    @drive_service.list_files(
      q: query_parts.join(' and '),
      fields: 'files(id,name,mimeType,modifiedTime,size)',
      page_size: 100,
      order_by: 'modifiedTime desc'
    ).files || []
  rescue Google::Apis::AuthorizationError
    refresh_token!
    retry
  end

  def download_file(file)
    refresh_token_if_needed!

    if google_native?(file.mime_type)
      export_google_file(file)
    else
      download_binary_file(file)
    end
  rescue Google::Apis::AuthorizationError
    refresh_token!
    retry
  end

  private

  def build_drive_service
    require 'google/apis/drive_v3'

    service = Google::Apis::DriveV3::DriveService.new
    service.authorization = build_credentials
    service
  end

  def build_credentials
    require 'signet/oauth_2/client'

    Signet::OAuth2::Client.new(
      client_id: GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil),
      client_secret: GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_SECRET', nil),
      token_credential_uri: 'https://oauth2.googleapis.com/token',
      access_token: @hook.access_token,
      refresh_token: @hook.settings['refresh_token'],
      expires_at: @hook.settings['expires_at']
    )
  end

  def refresh_token_if_needed!
    expires_at = @hook.settings['expires_at']
    return unless expires_at.present? && Time.at(expires_at.to_i) < 5.minutes.from_now

    refresh_token!
  end

  def refresh_token!
    creds = build_credentials
    creds.fetch_access_token!

    @hook.update!(
      access_token: creds.access_token,
      settings: @hook.settings.merge(
        'expires_at' => creds.expires_at&.to_i
      )
    )

    @drive_service.authorization = creds
  end

  def mime_type_query
    types = SUPPORTED_MIME_TYPES.map { |t| "mimeType = '#{t}'" }
    "(#{types.join(' or ')})"
  end

  def google_native?(mime_type)
    GOOGLE_NATIVE_TYPES.include?(mime_type)
  end

  def export_google_file(file)
    export_mime = case file.mime_type
                  when 'application/vnd.google-apps.document'
                    'text/plain'
                  when 'application/vnd.google-apps.spreadsheet'
                    'text/csv'
                  end

    io = StringIO.new
    @drive_service.export_file(file.id, export_mime, download_dest: io)
    io.rewind
    { content: io.read, type: :text, name: file.name }
  end

  def download_binary_file(file)
    io = StringIO.new
    io.set_encoding('ASCII-8BIT')
    @drive_service.get_file(file.id, download_dest: io)
    io.rewind
    { content: io, type: :binary, name: file.name, mime_type: file.mime_type }
  end
end
