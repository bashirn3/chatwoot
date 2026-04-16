class Integrations::Router::ProcessorService < Integrations::BotProcessorService
  pattr_initialize [:event_name!, :hook!, :event_data!]

  def perform
    message = event_data[:message]
    return if message.private?
    return unless processable_message?(message)
    return if bot_paused?
    return if recent_human_reply?

    process_content(message)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: hook&.account).capture_exception
  end

  private

  def bot_paused?
    conversation.additional_attributes&.dig('bot_paused') == true
  end

  def recent_human_reply?
    conversation.messages
                .where(message_type: :outgoing)
                .where.not(sender_type: [nil, ''])
                .where(sender_type: 'User')
                .where('created_at > ?', 10.minutes.ago)
                .exists?
  end

  def get_response(session_id, message_content)
    return nil if message_content.blank?

    if should_use_typebot?(message_content)
      delegate_to_typebot(session_id, message_content)
    else
      delegate_to_rag(session_id, message_content)
    end
  end

  def should_use_typebot?(message_content)
    active_typebot_session? || matches_trigger_keyword?(message_content) || router_mode == 'typebot_only'
  end

  def process_response(message, response)
    return if response.blank?

    if response[:source] == :typebot
      typebot_processor.send(:process_response, message, response[:data])
    elsif response[:source] == :rag
      rag_processor.send(:process_response, message, response[:data])
    end
  end

  def active_typebot_session?
    conversation.additional_attributes&.dig('typebot_session_id').present?
  end

  def matches_trigger_keyword?(message_content)
    keywords = trigger_keywords
    return false if keywords.blank?

    normalized = message_content.downcase.strip
    keywords.any? { |kw| normalized.start_with?(kw.downcase.strip) }
  end

  def delegate_to_typebot(session_id, message_content)
    response = typebot_processor.send(:get_response, session_id, message_content)
    return nil unless response

    { source: :typebot, data: response }
  end

  def delegate_to_rag(session_id, message_content)
    return nil unless rag_configured?

    response = rag_processor.send(:get_response, session_id, message_content)
    return nil unless response

    { source: :rag, data: response }
  end

  def typebot_processor
    @typebot_processor ||= Integrations::Typebot::ProcessorService.new(
      event_name: event_name, hook: hook, event_data: event_data
    )
  end

  def rag_processor
    @rag_processor ||= Integrations::Rag::ProcessorService.new(
      event_name: event_name, hook: hook, event_data: event_data
    )
  end

  def rag_configured?
    hook.settings['llm_api_key'].present?
  end

  def router_mode
    hook.settings['router_mode'] || 'auto'
  end

  def trigger_keywords
    raw = hook.settings['trigger_keywords']
    return [] if raw.blank?
    return raw if raw.is_a?(Array)

    raw.to_s.split(',').map(&:strip).reject(&:blank?)
  end
end
