# frozen_string_literal: true

class Whatsapp::TemplateManagementService
  include Rails.application.routes.url_helpers

  WHATSAPP_API_BASE = 'https://graph.facebook.com'
  API_VERSION = 'v18.0'

  attr_reader :template, :channel, :account

  def initialize(template:)
    @template = template
    @account = template.account
    @channel = template.channel_whatsapp || find_default_channel
  end

  # Submit template to Meta for approval
  def submit_template
    return error_response('No WhatsApp channel configured') unless channel
    return error_response('Template is not in draft status') unless template.status_draft?
    return error_response('Template validation failed', template.errors.full_messages) unless template.valid?

    waba_id = channel.provider_config['business_account_id']
    access_token = channel.provider_config['api_key']

    return error_response('WhatsApp Business Account ID not configured') if waba_id.blank?
    return error_response('Access token not configured') if access_token.blank?

    begin
      response = make_api_request(
        method: :post,
        url: "#{WHATSAPP_API_BASE}/#{API_VERSION}/#{waba_id}/message_templates",
        body: template.to_meta_payload,
        access_token: access_token
      )

      if response[:success]
        template.update!(
          meta_template_id: response[:data]['id'],
          status: 'PENDING',
          submitted_at: Time.current,
          meta_response: response[:data],
          last_synced_at: Time.current
        )

        success_response('Template submitted successfully', template)
      else
        handle_submission_error(response)
      end
    rescue StandardError => e
      Rails.logger.error("[WhatsApp Template] Submission error: #{e.message}")
      error_response("Failed to submit template: #{e.message}")
    end
  end

  # Sync template status from Meta
  def sync_status
    return error_response('Template has no Meta ID') if template.meta_template_id.blank?
    return error_response('No WhatsApp channel configured') unless channel

    waba_id = channel.provider_config['business_account_id']
    access_token = channel.provider_config['api_key']

    begin
      response = make_api_request(
        method: :get,
        url: "#{WHATSAPP_API_BASE}/#{API_VERSION}/#{template.meta_template_id}",
        params: { fields: 'name,status,category,language,quality_score,rejected_reason' },
        access_token: access_token
      )

      if response[:success]
        update_template_from_meta(response[:data])
        success_response('Template synced successfully', template)
      else
        error_response('Failed to sync template status', response[:error])
      end
    rescue StandardError => e
      Rails.logger.error("[WhatsApp Template] Sync error: #{e.message}")
      error_response("Failed to sync template: #{e.message}")
    end
  end

  # Delete template from Meta
  def delete_template
    return success_response('Template deleted locally', template) if template.meta_template_id.blank?
    return error_response('No WhatsApp channel configured') unless channel

    waba_id = channel.provider_config['business_account_id']
    access_token = channel.provider_config['api_key']

    begin
      response = make_api_request(
        method: :delete,
        url: "#{WHATSAPP_API_BASE}/#{API_VERSION}/#{waba_id}/message_templates",
        params: { name: template.name },
        access_token: access_token
      )

      if response[:success]
        template.destroy!
        success_response('Template deleted successfully')
      else
        # If template doesn't exist on Meta, still delete locally
        if response[:error]&.dig('code') == 100
          template.destroy!
          success_response('Template deleted locally (not found on Meta)')
        else
          error_response('Failed to delete template', response[:error])
        end
      end
    rescue StandardError => e
      Rails.logger.error("[WhatsApp Template] Delete error: #{e.message}")
      error_response("Failed to delete template: #{e.message}")
    end
  end

  # Fetch all templates from Meta and sync with local database
  def self.sync_all_templates(channel)
    return { success: false, error: 'No channel provided' } if channel.blank?

    waba_id = channel.provider_config['business_account_id']
    access_token = channel.provider_config['api_key']

    return { success: false, error: 'WABA ID not configured' } if waba_id.blank?

    begin
      response = new_api_request(
        method: :get,
        url: "#{WHATSAPP_API_BASE}/#{API_VERSION}/#{waba_id}/message_templates",
        params: { limit: 250, fields: 'id,name,status,category,language,quality_score,rejected_reason,components' },
        access_token: access_token
      )

      if response[:success]
        sync_templates_from_meta(channel, response[:data]['data'])
        { success: true, count: response[:data]['data'].length }
      else
        { success: false, error: response[:error] }
      end
    rescue StandardError => e
      Rails.logger.error("[WhatsApp Template] Sync all error: #{e.message}")
      { success: false, error: e.message }
    end
  end

  private

  def find_default_channel
    account.inboxes.find_by(channel_type: 'Channel::Whatsapp')&.channel
  end

  def make_api_request(method:, url:, body: nil, params: nil, access_token:)
    self.class.new_api_request(
      method: method,
      url: url,
      body: body,
      params: params,
      access_token: access_token
    )
  end

  def self.new_api_request(method:, url:, body: nil, params: nil, access_token:)
    conn = Faraday.new do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end

    headers = {
      'Authorization' => "Bearer #{access_token}",
      'Content-Type' => 'application/json'
    }

    response = case method
               when :get
                 conn.get(url, params, headers)
               when :post
                 conn.post(url, body.to_json, headers)
               when :delete
                 conn.delete(url) do |req|
                   req.params = params if params
                   req.headers = headers
                 end
               end

    if response.success?
      { success: true, data: response.body }
    else
      { success: false, error: response.body&.dig('error') || response.body }
    end
  end

  def handle_submission_error(response)
    error_data = response[:error]
    error_code = error_data&.dig('code')
    error_message = error_data&.dig('message') || 'Unknown error'

    # Map common Meta API errors to user-friendly messages
    user_message = case error_code
                   when 100
                     'Invalid template parameters. Please check your template content.'
                   when 190
                     'Access token expired. Please reconnect your WhatsApp channel.'
                   when 368
                     'Template name already exists. Please use a different name.'
                   when 131_000..131_999
                     parse_template_error(error_message)
                   else
                     "Template submission failed: #{error_message}"
                   end

    template.update!(
      status: 'REJECTED',
      rejection_reason: user_message,
      meta_response: error_data
    )

    error_response(user_message, error_data)
  end

  def parse_template_error(message)
    # Parse common template-specific errors
    if message.include?('variable')
      'Invalid variable format. Variables must be sequential ({{1}}, {{2}}, etc.)'
    elsif message.include?('button')
      'Invalid button configuration. Please check button text and URLs.'
    elsif message.include?('policy')
      'Template violates WhatsApp policy. Please review content guidelines.'
    else
      message
    end
  end

  def update_template_from_meta(data)
    new_status = map_meta_status(data['status'])
    
    updates = {
      status: new_status,
      quality_score: data['quality_score']&.dig('score'),
      last_synced_at: Time.current,
      meta_response: data
    }

    # Set rejection reason if rejected
    if new_status == 'REJECTED' && data['rejected_reason'].present?
      updates[:rejection_reason] = data['rejected_reason']
      updates[:rejected_at] = Time.current
    end

    # Set approved_at if newly approved
    if new_status == 'APPROVED' && !template.status_approved?
      updates[:approved_at] = Time.current
    end

    template.update!(updates)
  end

  def map_meta_status(meta_status)
    case meta_status&.upcase
    when 'APPROVED'
      'APPROVED'
    when 'PENDING', 'IN_APPEAL'
      'PENDING'
    when 'REJECTED'
      'REJECTED'
    when 'PAUSED', 'PENDING_DELETION'
      'PAUSED'
    when 'DISABLED', 'DELETED'
      'DISABLED'
    else
      'PENDING'
    end
  end

  def self.sync_templates_from_meta(channel, templates_data)
    templates_data.each do |meta_template|
      existing = WhatsappTemplate.find_by(
        account_id: channel.account_id,
        name: meta_template['name'],
        language: meta_template['language']
      )

      if existing
        # Update existing template
        existing.update!(
          meta_template_id: meta_template['id'],
          status: new.send(:map_meta_status, meta_template['status']),
          quality_score: meta_template['quality_score']&.dig('score'),
          rejection_reason: meta_template['rejected_reason'],
          last_synced_at: Time.current,
          meta_response: meta_template
        )
      else
        # Create new template from Meta
        create_template_from_meta(channel, meta_template)
      end
    end
  end

  def self.create_template_from_meta(channel, meta_template)
    components = meta_template['components'] || []
    
    header = components.find { |c| c['type'] == 'HEADER' }
    body = components.find { |c| c['type'] == 'BODY' }
    footer = components.find { |c| c['type'] == 'FOOTER' }
    buttons = components.find { |c| c['type'] == 'BUTTONS' }

    WhatsappTemplate.create!(
      account_id: channel.account_id,
      channel_whatsapp_id: channel.id,
      name: meta_template['name'],
      language: meta_template['language'],
      category: meta_template['category'],
      meta_template_id: meta_template['id'],
      status: new.send(:map_meta_status, meta_template['status']),
      quality_score: meta_template['quality_score']&.dig('score'),
      rejection_reason: meta_template['rejected_reason'],
      header_type: header&.dig('format'),
      header_content: header&.dig('text'),
      body_text: body&.dig('text') || '',
      footer_text: footer&.dig('text'),
      buttons: buttons&.dig('buttons')&.map { |b| normalize_button(b) },
      last_synced_at: Time.current,
      meta_response: meta_template
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[WhatsApp Template] Failed to create from Meta: #{e.message}")
  end

  def self.normalize_button(button)
    {
      'type' => button['type'],
      'text' => button['text'],
      'url' => button['url'],
      'phone_number' => button['phone_number'],
      'example' => button['example']
    }.compact
  end

  def success_response(message, data = nil)
    { success: true, message: message, data: data }
  end

  def error_response(message, details = nil)
    { success: false, error: message, details: details }
  end
end
