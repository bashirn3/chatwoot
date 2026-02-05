class Whatsapp::AccountStatusSyncService
  include Rails.application.routes.url_helpers

  def initialize(whatsapp_channel:)
    @whatsapp_channel = whatsapp_channel
    @provider_config = whatsapp_channel.provider_config
  end

  def perform
    return unless @whatsapp_channel.provider == 'whatsapp_cloud'
    return unless business_account_id.present? && api_key.present?

    sync_waba_status
    sync_phone_number_status
    update_sync_timestamp

    Rails.logger.info "[WHATSAPP] Account status synced for channel #{@whatsapp_channel.id}"
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Account status sync failed: #{e.message}"
    raise e
  end

  private

  def business_account_id
    @provider_config['business_account_id']
  end

  def api_key
    @provider_config['api_key']
  end

  def phone_number_id
    @provider_config['phone_number_id']
  end

  def base_url
    'https://graph.facebook.com/v18.0'
  end

  def sync_waba_status
    response = fetch_waba_data
    
    Rails.logger.info "[WHATSAPP SYNC] WABA Response for channel #{@whatsapp_channel.id}: #{response.code} - #{response.body}"
    
    unless response.success?
      Rails.logger.error "[WHATSAPP SYNC] WABA fetch failed: #{response.code} - #{response.body}"
      return
    end

    data = response.parsed_response
    Rails.logger.info "[WHATSAPP SYNC] WABA data parsed: #{data.inspect}"

    # Update account status - Meta returns this in different formats
    account_status = data['account_status'] || data['status']
    if account_status.present?
      Rails.logger.info "[WHATSAPP SYNC] Updating account status to: #{account_status}"
      @whatsapp_channel.update_status(account_status.upcase, source: 'API_SYNC')
    end

    # Update business verification status
    if data['business_verification_status'].present?
      Rails.logger.info "[WHATSAPP SYNC] Updating business_verification_status to: #{data['business_verification_status']}"
      update_field_with_event(
        field: :business_verification_status,
        new_value: data['business_verification_status'],
        event_type: 'VERIFICATION_CHANGE'
      )
    end

    # Update account review status
    if data['account_review_status'].present?
      Rails.logger.info "[WHATSAPP SYNC] Updating account_review_status to: #{data['account_review_status']}"
      update_field_with_event(
        field: :account_review_status,
        new_value: data['account_review_status'],
        event_type: 'ACCOUNT_REVIEW_CHANGE'
      )
    end

    # Check for message_template_namespace (indicates if account can send templates)
    if data['message_template_namespace'].present?
      Rails.logger.info "[WHATSAPP SYNC] Account has template namespace: #{data['message_template_namespace']}"
    end

    # Store any violation or restriction info
    if data['violations'].present?
      data['violations'].each do |violation|
        @whatsapp_channel.record_violation(
          violation_type: violation['violation_type'],
          details: violation,
          source: 'API_SYNC'
        )
      end
    end
  end

  def sync_phone_number_status
    return unless phone_number_id.present?

    response = fetch_phone_number_data
    
    Rails.logger.info "[WHATSAPP SYNC] Phone number response for channel #{@whatsapp_channel.id}: #{response.code} - #{response.body}"
    
    unless response.success?
      Rails.logger.error "[WHATSAPP SYNC] Phone number fetch failed: #{response.code} - #{response.body}"
      return
    end

    data = response.parsed_response
    Rails.logger.info "[WHATSAPP SYNC] Phone number data parsed: #{data.inspect}"

    # Update quality rating - can be nested or flat
    quality = nil
    if data['quality_score'].is_a?(Hash)
      quality = data['quality_score']['score']
    elsif data['quality_score'].is_a?(String)
      quality = data['quality_score']
    elsif data['quality_rating'].present?
      quality = data['quality_rating']
    end
    
    if quality.present?
      Rails.logger.info "[WHATSAPP SYNC] Updating quality rating to: #{quality}"
      @whatsapp_channel.update_quality_rating(quality.upcase, source: 'API_SYNC')
    end

    # Update messaging limits
    if data['messaging_limit_tier'].present?
      Rails.logger.info "[WHATSAPP SYNC] Updating messaging_limit_tier to: #{data['messaging_limit_tier']}"
      update_field_with_event(
        field: :messaging_limit_tier,
        new_value: data['messaging_limit_tier'],
        event_type: 'MESSAGING_LIMIT_CHANGE'
      )
    end

    # Update throughput - can be nested or flat
    throughput = nil
    if data['throughput'].is_a?(Hash)
      throughput = data['throughput']['level']
    elsif data['throughput'].present?
      throughput = data['throughput']
    end
    
    if throughput.present?
      Rails.logger.info "[WHATSAPP SYNC] Updating throughput to: #{throughput}"
      update_field_with_event(
        field: :current_throughput,
        new_value: throughput.to_s,
        event_type: 'THROUGHPUT_CHANGE'
      )
    end

    # Update display name status
    if data['display_name_status'].present?
      Rails.logger.info "[WHATSAPP SYNC] Updating display_name_status to: #{data['display_name_status']}"
      update_field_with_event(
        field: :display_name_status,
        new_value: data['display_name_status'],
        event_type: 'DISPLAY_NAME_CHANGE'
      )
    end

    # Update status from phone number level - this often shows BANNED/RESTRICTED at phone level
    phone_status = data['status'] || data['account_mode']
    if phone_status.present?
      normalized_status = normalize_phone_status(phone_status)
      if normalized_status && normalized_status != @whatsapp_channel.account_status
        Rails.logger.info "[WHATSAPP SYNC] Updating status from phone number to: #{normalized_status}"
        @whatsapp_channel.update_status(normalized_status, source: 'API_SYNC')
      end
    end
    
    # Check for is_official_business_account flag
    if data.key?('is_official_business_account')
      Rails.logger.info "[WHATSAPP SYNC] is_official_business_account: #{data['is_official_business_account']}"
    end
  end
  
  def normalize_phone_status(status)
    # Meta returns various status values, normalize to our known statuses
    status_mapping = {
      'CONNECTED' => 'ACTIVE',
      'DISCONNECTED' => 'DISABLED',
      'BANNED' => 'BANNED',
      'FLAGGED' => 'FLAGGED',
      'RESTRICTED' => 'RESTRICTED',
      'PENDING' => 'ACTIVE',
      'ACTIVE' => 'ACTIVE',
      'DISABLED' => 'DISABLED',
      'PENDING_DELETION' => 'PENDING_DELETION'
    }
    status_mapping[status.upcase] || status.upcase
  end

  def fetch_waba_data
    url = "#{base_url}/#{business_account_id}"
    # Request all available status fields from WABA
    fields = 'id,name,account_status,business_verification_status,account_review_status,message_template_namespace,on_behalf_of_business_info,ownership_type,primary_funding_id,timezone_id'
    
    HTTParty.get(
      url,
      query: { fields: fields },
      headers: api_headers
    )
  end

  def fetch_phone_number_data
    url = "#{base_url}/#{phone_number_id}"
    # Request all available status fields from phone number endpoint
    fields = 'id,display_phone_number,verified_name,quality_score,quality_rating,messaging_limit_tier,throughput,status,display_name_status,code_verification_status,is_official_business_account,account_mode,platform_type,name_status'
    
    HTTParty.get(
      url,
      query: { fields: fields },
      headers: api_headers
    )
  end

  def api_headers
    {
      'Authorization' => "Bearer #{api_key}",
      'Content-Type' => 'application/json'
    }
  end

  def update_field_with_event(field:, new_value:, event_type:)
    old_value = @whatsapp_channel.send(field)
    return if old_value == new_value

    @whatsapp_channel.update!(field => new_value)
    @whatsapp_channel.send(:record_status_event,
      event_type: event_type,
      previous_value: old_value&.to_s,
      new_value: new_value.to_s,
      source: 'API_SYNC'
    )
  end

  def update_sync_timestamp
    @whatsapp_channel.update!(account_status_last_synced_at: Time.current)
  end
end
