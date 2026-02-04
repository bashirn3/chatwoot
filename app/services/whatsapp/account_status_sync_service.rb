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
    return unless response.success?

    data = response.parsed_response

    # Update account status
    if data['account_status'].present?
      @whatsapp_channel.update_status(data['account_status'], source: 'API_SYNC')
    end

    # Update business verification status
    if data['business_verification_status'].present?
      update_field_with_event(
        field: :business_verification_status,
        new_value: data['business_verification_status'],
        event_type: 'VERIFICATION_CHANGE'
      )
    end

    # Update account review status
    if data['account_review_status'].present?
      update_field_with_event(
        field: :account_review_status,
        new_value: data['account_review_status'],
        event_type: 'ACCOUNT_REVIEW_CHANGE'
      )
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
    return unless response.success?

    data = response.parsed_response

    # Update quality rating
    if data['quality_score']
      quality = data['quality_score']['score'] || data['quality_score']
      @whatsapp_channel.update_quality_rating(quality, source: 'API_SYNC')
    end

    # Update messaging limits
    if data['messaging_limit_tier'].present?
      update_field_with_event(
        field: :messaging_limit_tier,
        new_value: data['messaging_limit_tier'],
        event_type: 'MESSAGING_LIMIT_CHANGE'
      )
    end

    # Update throughput
    if data['throughput'].present?
      throughput = data['throughput']['level']
      update_field_with_event(
        field: :current_throughput,
        new_value: throughput.to_s,
        event_type: 'THROUGHPUT_CHANGE'
      )
    end

    # Update display name status
    if data['display_name_status'].present?
      update_field_with_event(
        field: :display_name_status,
        new_value: data['display_name_status'],
        event_type: 'DISPLAY_NAME_CHANGE'
      )
    end

    # Update status from phone number level
    if data['status'].present? && data['status'] != @whatsapp_channel.account_status
      @whatsapp_channel.update_status(data['status'], source: 'API_SYNC')
    end
  end

  def fetch_waba_data
    url = "#{base_url}/#{business_account_id}"
    fields = 'id,name,account_status,business_verification_status,account_review_status'
    
    HTTParty.get(
      url,
      query: { fields: fields },
      headers: api_headers
    )
  end

  def fetch_phone_number_data
    url = "#{base_url}/#{phone_number_id}"
    fields = 'id,display_phone_number,verified_name,quality_score,messaging_limit_tier,throughput,status,display_name_status'
    
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
