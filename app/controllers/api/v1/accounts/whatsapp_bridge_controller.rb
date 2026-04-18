class Api::V1::Accounts::WhatsappBridgeController < Api::V1::Accounts::BaseController
  include Api::V1::Accounts::WhatsappBridgeSettings

  before_action :check_admin_authorization?, except: [:incoming_webhook, :outgoing_webhook]
  before_action :validate_bridge_config, except: [:incoming_webhook, :outgoing_webhook, :regions]
  skip_before_action :authenticate_user!, only: [:incoming_webhook, :outgoing_webhook]
  skip_before_action :authenticate_access_token!, only: [:incoming_webhook, :outgoing_webhook]

  # GET /regions
  # Returns active regions (no secrets) for the onboarding country picker.
  def regions
    payload = WhatsappBridge::RegionRegistry.active.values.map(&:to_public_h)
    render json: { success: true, regions: payload }
  end

  # POST /resolve_region { country_iso }
  # Resolves a country to a concrete region code, performing the UK
  # tie-break (via each region's /api/proxy/pool) when needed.
  def resolve_region
    iso = params[:country_iso].to_s.upcase
    region_code = WhatsappBridge::RegionResolver.new(iso).resolve
    region = WhatsappBridge::RegionRegistry.for(region_code)
    render json: {
      success: true,
      region_code: region_code,
      country: region.country,
      label: region.label,
      lat: region.lat,
      lng: region.lng
    }
  rescue WhatsappBridge::RegionResolver::UnsupportedCountryError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue WhatsappBridge::RegionResolver::TemporarilyUnavailableError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  # GET /instances
  # Lists this account's WhatsApp bridge instances. Sourced from the local DB
  # (every Channel::Api tagged with whatsapp_bridge_instance_id), enriched
  # with the last-known connection status stored by the periodic sync job.
  # This replaces the old single-framework scan; orphan detection for the
  # legacy framework is still performed for backward compatibility.
  def instances
    linked = bridge_linked_inboxes
    instances = linked.map { |inbox| instance_payload_from_inbox(inbox) }

    render json: {
      success: true,
      instances: instances,
      orphaned_inboxes: legacy_orphan_inboxes(linked)
    }
  end

  def relink_instance
    scoped_name = params[:instance_name]
    region_code = params[:region_code].presence || legacy_region_code
    display_name = scoped_name.sub(/\Aacct-\d+-/, '')
    inbox = create_api_channel_inbox(display_name, scoped_name, region_code)
    inbox.channel.update!(webhook_url: outgoing_webhook_url(scoped_name))

    webhook_url = incoming_webhook_url(inbox.channel.identifier)
    WhatsappBridge::RegionalClient.new(region_code).put("/api/instances/#{scoped_name}", { webhookUrl: webhook_url })

    render json: { success: true, inbox_id: inbox.id }
  end

  def delete_inbox
    inbox = Current.account.inboxes.find(params[:inbox_id])
    inbox.destroy
    render json: { success: true }
  end

  # POST /create_instance
  # Body: { instance_name, country_iso?, region_code? }
  # - country_iso takes precedence (we resolve → region_code including UK tie-break).
  # - region_code can be provided directly (advanced callers / tests).
  # - neither → fall back to legacy single-region.
  def create_instance
    region_code = resolve_requested_region
    return render_region_error if region_code.blank?

    name = params[:instance_name].presence || "wa-#{SecureRandom.hex(4)}"
    scoped_name = scoped_instance_id(name)
    inbox = create_api_channel_inbox(name, scoped_name, region_code)
    webhook_url = incoming_webhook_url(inbox.channel.identifier)

    response = WhatsappBridge::RegionalClient.new(region_code).post(
      '/api/instances',
      id: scoped_name, name: scoped_name, webhookUrl: webhook_url
    )

    if response['error'].present?
      inbox.destroy
      render json: { error: response['error'] }, status: :unprocessable_entity
      return
    end

    inbox.channel.update!(webhook_url: outgoing_webhook_url(scoped_name))
    instance_data = response['instance'] || response
    instance_data['region'] = region_code
    render json: { success: true, instance: instance_data, inbox_id: inbox.id, region_code: region_code }
  end

  def connect
    body = params[:pairing_phone].present? ? { pairingPhone: params[:pairing_phone] } : nil
    render json: client_for_instance(params[:instance_name]).post(
      "/api/instances/#{params[:instance_name]}/connect", body
    )
  end

  def qr_code
    render json: client_for_instance(params[:instance_name]).get(
      "/api/instances/#{params[:instance_name]}/qr"
    )
  end

  def connection_state
    render json: client_for_instance(params[:instance_name]).get(
      "/api/instances/#{params[:instance_name]}/connection"
    )
  end

  def disconnect
    render json: client_for_instance(params[:instance_name]).post(
      "/api/instances/#{params[:instance_name]}/disconnect"
    )
  end

  def delete_instance
    instance_name = params[:instance_name]
    # If a linked inbox exists, destroying it triggers the Channel::Api
    # after_destroy_commit callback which calls the framework DELETE via
    # the channel's persisted region. If no inbox is linked (true orphan),
    # we clean up via the legacy region for backward compatibility.
    if find_and_destroy_inbox(instance_name)
      render json: { success: true }
    else
      render json: client_for_instance(instance_name).delete("/api/instances/#{instance_name}")
    end
  end

  def incoming_webhook
    channel = Channel::Api.find_by!(identifier: params[:identifier])
    message = WhatsappBridge::IncomingMessageService.new(inbox: channel.inbox, params: webhook_params).perform
    if message
      render json: { success: true, message_id: message.id }
    else
      head :ok
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "WhatsApp bridge webhook error: #{e.message}"
    head :ok
  end

  def outgoing_webhook
    return head :ok unless outgoing_message_event?

    phone = extract_phone_from_payload
    return head :ok if phone.blank?

    send_outgoing_message(phone)
    head :ok
  end

  private

  # Any configured region is enough to let the controller serve requests.
  # Keeps legacy-only deployments working while we roll out regional vars.
  def validate_bridge_config
    return if WhatsappBridge::RegionRegistry.configured.any?

    render json: { error: 'WhatsApp Bridge not configured.' }, status: :service_unavailable
  end

  def scoped_instance_id(name)
    "acct-#{Current.account.id}-#{name}"
  end

  def account_instance?(instance)
    name = instance['id'] || instance['name'] || instance.dig('instance', 'instanceName') || ''
    name.start_with?("acct-#{Current.account.id}-")
  end

  def legacy_region_code
    WhatsappBridge::RegionRegistry.legacy&.code || 'legacy'
  end

  # Returns the client that should own an existing instance, based on the
  # region recorded against its Channel::Api row. Falls back to 'legacy'
  # for instances created before the multi-region rollout.
  def client_for_instance(instance_name)
    channel = find_channel_by_instance_id(instance_name)
    region_code = channel&.whatsapp_bridge_region || legacy_region_code
    WhatsappBridge::RegionalClient.new(region_code)
  end

  def find_channel_by_instance_id(instance_name)
    Current.account.api_channels.find do |channel|
      channel.additional_attributes&.dig('whatsapp_bridge_instance_id') == instance_name
    end
  end

  def resolve_requested_region
    if params[:country_iso].present?
      WhatsappBridge::RegionResolver.new(params[:country_iso]).resolve
    elsif params[:region_code].present?
      params[:region_code].to_s.downcase
    else
      legacy_region_code
    end
  rescue WhatsappBridge::RegionResolver::UnsupportedCountryError,
         WhatsappBridge::RegionResolver::TemporarilyUnavailableError => e
    @region_resolve_error = e
    nil
  end

  def render_region_error
    message = @region_resolve_error&.message || 'Could not resolve region'
    status  = case @region_resolve_error
              when WhatsappBridge::RegionResolver::UnsupportedCountryError then :unprocessable_entity
              when WhatsappBridge::RegionResolver::TemporarilyUnavailableError then :service_unavailable
              else :unprocessable_entity
              end
    render json: { error: message }, status: status
  end

  def instance_payload_from_inbox(inbox)
    attrs = inbox.channel.additional_attributes || {}
    {
      'id' => attrs['whatsapp_bridge_instance_id'],
      'name' => inbox.name,
      'region' => attrs['whatsapp_bridge_region'] || legacy_region_code,
      'status' => attrs['whatsapp_bridge_connection_status'],
      'last_checked_at' => attrs['whatsapp_bridge_last_checked_at'],
      'inbox_id' => inbox.id,
      'has_inbox' => true
    }
  end

  # Minimal orphan detection: only look at the legacy region (where any
  # pre-rollout orphans live). Regional deployments cannot accumulate
  # orphans because Channel::Api.after_destroy_commit keeps them in sync.
  def legacy_orphan_inboxes(linked_inboxes)
    return [] unless WhatsappBridge::RegionRegistry.legacy&.configured?

    response = WhatsappBridge::RegionalClient.new(legacy_region_code).get('/api/instances')
    framework_ids = extract_framework_instance_ids(response)
    return [] if framework_ids.nil?

    legacy_linked = linked_inboxes.select do |inbox|
      (inbox.channel.additional_attributes['whatsapp_bridge_region'].presence || legacy_region_code) == legacy_region_code
    end
    orphans = legacy_linked.reject { |inbox| framework_ids.include?(inbox.channel.additional_attributes['whatsapp_bridge_instance_id']) }
    orphans.map do |inbox|
      { id: inbox.channel.additional_attributes['whatsapp_bridge_instance_id'],
        name: inbox.name, status: 'orphaned', inbox_id: inbox.id,
        conversations_count: inbox.conversations.count }
    end
  end

  def extract_framework_instance_ids(response)
    return nil unless response.is_a?(Hash)
    return nil if response['error'].present?

    list = response['instances'] || []
    list.select { |i| account_instance?(i) }.map { |i| i['id'] || i['name'] }.compact
  end

  def bridge_linked_inboxes
    Current.account.inboxes.joins('INNER JOIN channel_api ON channel_api.id = inboxes.channel_id').where(
      inboxes: { channel_type: 'Channel::Api' }
    ).select { |inbox| inbox.channel.additional_attributes&.key?('whatsapp_bridge_instance_id') }
  end

  def create_api_channel_inbox(display_name, scoped_name, region_code = nil)
    region_code ||= legacy_region_code
    channel = Current.account.api_channels.create!(
      additional_attributes: {
        'whatsapp_bridge_instance_id' => scoped_name,
        'whatsapp_bridge_region' => region_code
      }
    )
    Current.account.inboxes.create!(name: "WhatsApp - #{display_name}", channel: channel)
  end

  def find_and_destroy_inbox(instance_name)
    Current.account.inboxes.joins('INNER JOIN channel_api ON channel_api.id = inboxes.channel_id').where(
      inboxes: { channel_type: 'Channel::Api' }
    ).find_each do |inbox|
      next unless inbox.channel.additional_attributes&.dig('whatsapp_bridge_instance_id') == instance_name

      inbox.destroy
      return true
    end
    false
  end

  def incoming_webhook_url(identifier)
    host = ENV.fetch('FRONTEND_URL', '')
    "#{host}/api/v1/whatsapp_bridge/accounts/#{Current.account.id}/webhook/#{identifier}"
  end

  def outgoing_webhook_url(instance_name)
    host = ENV.fetch('FRONTEND_URL', '')
    "#{host}/api/v1/whatsapp_bridge/accounts/#{Current.account.id}/outgoing/#{instance_name}"
  end

  def webhook_params
    params.permit(:from_phone, :to_phone, :message, :message_id, :media_url, :media_type, :mime_type, :file_name,
                  :sender_phone, :sender_name, :is_group, :group_name)
  end

  def send_outgoing_message(phone)
    send_path = "/api/instances/#{params[:instance_name]}/send"
    client = client_for_instance(params[:instance_name])
    attachments = params[:attachments] || []
    if attachments.present?
      att = attachments.first
      media_url = absolute_url(att[:data_url])
      client.post(send_path, { to: phone, message: params[:content].to_s,
                               messageType: att[:file_type], mediaUrl: media_url })
    elsif params[:content].present?
      client.post(send_path, { to: phone, message: params[:content] })
    end
  end

  def absolute_url(url)
    return url if url.blank? || url.start_with?('http')

    "#{ENV.fetch('FRONTEND_URL', '')}#{url}"
  end

  def outgoing_message_event?
    params[:event] == 'message_created' && params[:message_type] == 'outgoing' && !params[:private]
  end

  def extract_phone_from_payload
    contact_id = params.dig(:conversation, :contact_id) || params.dig(:conversation, :meta, :sender, :id)
    return nil unless contact_id

    Contact.find_by(id: contact_id)&.phone_number&.gsub(/\D/, '')
  end

  # Shortcut used by the settings concern for per-instance framework calls.
  def regional_client_for_instance(instance_name)
    client_for_instance(instance_name)
  end
end
