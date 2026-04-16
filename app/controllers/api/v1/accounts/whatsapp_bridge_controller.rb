class Api::V1::Accounts::WhatsappBridgeController < Api::V1::Accounts::BaseController
  include Api::V1::Accounts::WhatsappBridgeSettings

  before_action :check_admin_authorization?, except: [:incoming_webhook, :outgoing_webhook]
  before_action :validate_bridge_config, except: [:incoming_webhook, :outgoing_webhook]
  skip_before_action :authenticate_user!, only: [:incoming_webhook, :outgoing_webhook]
  skip_before_action :authenticate_access_token!, only: [:incoming_webhook, :outgoing_webhook]

  def instances
    response = framework_request(:get, '/api/instances')
    all_instances = response.is_a?(Hash) ? (response['instances'] || []) : []
    scoped = all_instances.select { |i| account_instance?(i) }

    linked = bridge_linked_inboxes
    inbox_by_bridge_id = linked.index_by { |inbox| inbox.channel.additional_attributes['whatsapp_bridge_instance_id'] }

    bridge_instance_ids = scoped.map { |i| i['id'] || i['name'] }.compact
    scoped.each do |inst|
      inst_id = inst['id'] || inst['name']
      inbox = inbox_by_bridge_id[inst_id]
      inst['inbox_id'] = inbox&.id
      inst['has_inbox'] = inbox.present?
    end

    orphaned = linked.reject { |inbox|
      bridge_instance_ids.include?(inbox.channel.additional_attributes['whatsapp_bridge_instance_id'])
    }
    orphaned_data = orphaned.map { |inbox|
      { id: inbox.channel.additional_attributes['whatsapp_bridge_instance_id'],
        name: inbox.name, status: 'orphaned', inbox_id: inbox.id,
        conversations_count: inbox.conversations.count }
    }

    render json: { success: true, instances: scoped, orphaned_inboxes: orphaned_data }
  end

  def relink_instance
    scoped_name = params[:instance_name]
    display_name = scoped_name.sub(/\Aacct-\d+-/, '')
    inbox = create_api_channel_inbox(display_name, scoped_name)
    inbox.channel.update!(webhook_url: outgoing_webhook_url(scoped_name))

    webhook_url = incoming_webhook_url(inbox.channel.identifier)
    framework_request(:put, "/api/instances/#{scoped_name}", { webhookUrl: webhook_url })

    render json: { success: true, inbox_id: inbox.id }
  end

  def delete_inbox
    inbox = Current.account.inboxes.find(params[:inbox_id])
    inbox.destroy
    render json: { success: true }
  end

  def create_instance
    name = params[:instance_name].presence || "wa-#{SecureRandom.hex(4)}"
    scoped_name = scoped_instance_id(name)
    inbox = create_api_channel_inbox(name, scoped_name)
    webhook_url = incoming_webhook_url(inbox.channel.identifier)

    response = framework_request(:post, '/api/instances', {
                                   id: scoped_name, name: scoped_name, webhookUrl: webhook_url
                                 })

    if response['error'].present?
      inbox.destroy
      render json: { error: response['error'] }, status: :unprocessable_entity
      return
    end

    inbox.channel.update!(webhook_url: outgoing_webhook_url(scoped_name))
    instance_data = response['instance'] || response
    render json: { success: true, instance: instance_data, inbox_id: inbox.id }
  end

  def connect
    body = params[:pairing_phone].present? ? { pairingPhone: params[:pairing_phone] } : nil
    render json: framework_request(:post, "/api/instances/#{params[:instance_name]}/connect", body)
  end

  def qr_code
    render json: framework_request(:get, "/api/instances/#{params[:instance_name]}/qr")
  end

  def connection_state
    render json: framework_request(:get, "/api/instances/#{params[:instance_name]}/connection")
  end

  def disconnect
    render json: framework_request(:post, "/api/instances/#{params[:instance_name]}/disconnect")
  end

  def delete_instance
    instance_name = params[:instance_name]
    find_and_destroy_inbox(instance_name)
    render json: framework_request(:delete, "/api/instances/#{instance_name}")
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

  def framework_base_url
    @framework_base_url ||= ENV.fetch('WHATSAPP_BRIDGE_URL', nil)
  end

  def framework_api_key
    @framework_api_key ||= ENV.fetch('WHATSAPP_BRIDGE_API_KEY', nil)
  end

  def validate_bridge_config
    return if framework_base_url.present?

    render json: { error: 'WhatsApp Bridge not configured.' }, status: :service_unavailable
  end

  def scoped_instance_id(name)
    "acct-#{Current.account.id}-#{name}"
  end

  def account_instance?(instance)
    name = instance['id'] || instance['name'] || instance.dig('instance', 'instanceName') || ''
    name.start_with?("acct-#{Current.account.id}-")
  end

  def framework_request(method, path, body = nil)
    headers = { 'Content-Type' => 'application/json' }
    headers['X-API-Key'] = framework_api_key if framework_api_key.present?
    options = { headers: headers }
    options[:body] = body.to_json if body.present?

    response = HTTParty.send(method, "#{framework_base_url}#{path}", options)
    JSON.parse(response.body)
  rescue StandardError => e
    { 'error' => e.message }
  end

  def bridge_linked_inboxes
    Current.account.inboxes.joins('INNER JOIN channel_api ON channel_api.id = inboxes.channel_id').where(
      inboxes: { channel_type: 'Channel::Api' }
    ).select { |inbox| inbox.channel.additional_attributes&.key?('whatsapp_bridge_instance_id') }
  end

  def create_api_channel_inbox(display_name, scoped_name)
    channel = Current.account.api_channels.create!(
      additional_attributes: { 'whatsapp_bridge_instance_id' => scoped_name }
    )
    Current.account.inboxes.create!(name: "WhatsApp - #{display_name}", channel: channel)
  end

  def find_and_destroy_inbox(instance_name)
    Current.account.inboxes.joins('INNER JOIN channel_api ON channel_api.id = inboxes.channel_id').where(
      inboxes: { channel_type: 'Channel::Api' }
    ).find_each do |inbox|
      next unless inbox.channel.additional_attributes&.dig('whatsapp_bridge_instance_id') == instance_name

      inbox.destroy
      break
    end
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
    attachments = params[:attachments] || []
    if attachments.present?
      att = attachments.first
      media_url = absolute_url(att[:data_url])
      framework_request(:post, send_path, { to: phone, message: params[:content].to_s,
                                            messageType: att[:file_type], mediaUrl: media_url })
    elsif params[:content].present?
      framework_request(:post, send_path, { to: phone, message: params[:content] })
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
end
