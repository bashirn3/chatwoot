class Integrations::Typebot::ProcessorService < Integrations::BotProcessorService
  pattr_initialize [:event_name!, :hook!, :event_data!]

  private

  def get_response(_session_id, message_content)
    typebot_session_id = conversation.additional_attributes&.dig('typebot_session_id')

    if typebot_session_id.present?
      continue_chat(typebot_session_id, message_content)
    else
      start_chat(message_content)
    end
  rescue StandardError => e
    Rails.logger.error "Typebot Error: (account-#{hook.try(:account_id)}, hook-#{hook.id}) #{e.message}"
    nil
  end

  def process_response(message, response)
    return if response.blank?

    messages = response['messages'] || []
    input = response['input']

    messages.each do |bot_message|
      content_params = build_content_params(bot_message)
      next if content_params.blank?

      create_outgoing_message(message, content_params)
    end

    handle_input_block(message, input) if input.present?
    handle_client_side_actions(message, response['clientSideActions']) if response['clientSideActions'].present?
  end

  def start_chat(message_content)
    url = "#{typebot_url}/api/v1/typebots/#{public_id}/startChat"
    body = { message: message_content }
    body[:prefilledVariables] = prefilled_variables

    response = make_request(:post, url, body)
    return nil unless response

    store_session_id(response['sessionId']) if response['sessionId'].present?
    response
  end

  def continue_chat(session_id, message_content)
    url = "#{typebot_url}/api/v1/sessions/#{session_id}/continueChat"
    body = { message: message_content }

    response = make_request(:post, url, body)
    return nil unless response

    store_session_id(response['sessionId']) if response['sessionId'].present?
    response
  end

  def build_content_params(bot_message)
    case bot_message['type']
    when 'text'
      build_text_params(bot_message)
    when 'image'
      build_media_params(bot_message, :image)
    when 'video'
      build_media_params(bot_message, :video)
    when 'audio'
      build_media_params(bot_message, :audio)
    end
  end

  def build_text_params(bot_message)
    content = extract_text_content(bot_message)
    return nil if content.blank?

    { content: content }
  end

  def build_media_params(bot_message, type)
    url = bot_message.dig('content', 'url')
    return nil if url.blank?

    { content: url, content_type: type }
  end

  def extract_text_content(bot_message)
    rich_text = bot_message.dig('content', 'richText')
    return nil unless rich_text.is_a?(Array)

    rich_text.filter_map { |block| extract_block_text(block) }.join("\n")
  end

  def extract_block_text(block)
    children = block['children']
    return nil unless children.is_a?(Array)

    children.filter_map do |child|
      if child['text'].present?
        apply_formatting(child)
      elsif child['type'] == 'a'
        child.dig('children', 0, 'text')
      end
    end.join
  end

  def apply_formatting(child)
    text = child['text']
    text = "*#{text}*" if child['bold']
    text = "_#{text}_" if child['italic']
    text
  end

  def handle_input_block(message, input)
    return unless input['type'] == 'choice input'

    items = input['items'] || []
    return if items.empty?

    buttons = items.map { |item| { title: item['content'], payload: item['content'] } }
    create_outgoing_message(message, {
                              content: '',
                              content_type: 'input_select',
                              content_attributes: { items: buttons }
                            })
  end

  def handle_client_side_actions(message, actions)
    actions.each do |action|
      next unless action['type'] == 'chatwoot'

      chatwoot_action = action.dig('chatwoot', 'task')
      case chatwoot_action
      when 'showWidget', 'open'
        process_action(message, 'handoff')
      when 'close'
        process_action(message, 'resolve')
      end
    end
  end

  def create_outgoing_message(message, content_params)
    return if content_params.blank?

    conversation = message.conversation
    conversation.messages.create!(
      content_params.merge(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id
      )
    )
  end

  def store_session_id(session_id)
    attrs = conversation.additional_attributes || {}
    attrs['typebot_session_id'] = session_id
    conversation.update!(additional_attributes: attrs)
  end

  def prefilled_variables
    contact = conversation.contact
    {
      'chatwootContactName' => contact.name,
      'chatwootContactEmail' => contact.email,
      'chatwootContactPhone' => contact.phone_number,
      'chatwootConversationId' => conversation.display_id.to_s
    }.compact
  end

  def typebot_url
    hook.settings['typebot_url'].to_s.chomp('/')
  end

  def public_id
    hook.settings['public_id']
  end

  def api_token
    hook.settings['api_token']
  end

  def make_request(method, url, body)
    headers = { 'Content-Type' => 'application/json' }
    headers['Authorization'] = "Bearer #{api_token}" if api_token.present?

    response = HTTParty.send(method, url, body: body.to_json, headers: headers, timeout: 15)

    return nil unless response.success?

    response.parsed_response
  end
end
