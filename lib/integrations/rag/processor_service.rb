class Integrations::Rag::ProcessorService < Integrations::BotProcessorService
  pattr_initialize [:event_name!, :hook!, :event_data!]

  TOP_K = 5
  DEFAULT_CONFIDENCE_THRESHOLD = 0.6

  private

  def get_response(_session_id, message_content)
    return nil if message_content.blank?

    embedding = generate_embedding(message_content)
    return nil unless embedding

    context_chunks = search_knowledge_base(embedding)
    return nil if context_chunks.empty?

    answer = call_llm(message_content, context_chunks)
    return nil unless answer

    answer
  rescue StandardError => e
    Rails.logger.error "RAG Error: (account-#{hook.try(:account_id)}, hook-#{hook.id}) #{e.message}"
    nil
  end

  def process_response(message, response)
    return if response.blank?

    content = response[:content]
    confidence = response[:confidence] || 0.0

    create_outgoing_message(message, { content: content }) if content.present?

    return unless confidence < confidence_threshold

    message.conversation.bot_handoff!
  end

  def generate_embedding(text)
    response = HTTParty.post(
      "#{api_base}/embeddings",
      headers: llm_headers,
      body: { model: embedding_model, input: text }.to_json,
      timeout: 15
    )

    return nil unless response.success?

    response.parsed_response.dig('data', 0, 'embedding')
  end

  def search_knowledge_base(embedding)
    KnowledgeEmbedding
      .for_account(hook.account_id)
      .nearest_neighbors(:embedding, embedding, distance: :cosine)
      .limit(TOP_K)
      .map { |record| { content: record.content, distance: record.neighbor_distance } }
  end

  def call_llm(question, context_chunks)
    context_text = context_chunks.pluck(:content).join("\n\n---\n\n")

    messages = [
      { role: 'system', content: system_prompt_with_context(context_text) },
      { role: 'user', content: question }
    ]

    response = HTTParty.post(
      "#{api_base}/chat/completions",
      headers: llm_headers,
      body: { model: llm_model, messages: messages, temperature: 0.3 }.to_json,
      timeout: 30
    )

    return nil unless response.success?

    answer_text = response.parsed_response.dig('choices', 0, 'message', 'content')
    return nil if answer_text.blank?

    avg_distance = context_chunks.sum { |c| c[:distance] } / context_chunks.size.to_f
    confidence = [(1.0 - avg_distance).round(2), 0.0].max

    { content: answer_text, confidence: confidence }
  end

  def system_prompt_with_context(context_text)
    base_prompt = custom_system_prompt.presence || default_system_prompt
    "#{base_prompt}\n\nContext:\n#{context_text}"
  end

  def default_system_prompt
    <<~PROMPT.squish
      You are a helpful customer support assistant. Answer questions based ONLY on the provided context.
      If the context does not contain enough information to answer confidently, say so honestly.
      Be concise and direct. Do not make up information.
    PROMPT
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

  def llm_headers
    headers = { 'Content-Type' => 'application/json' }
    headers['Authorization'] = "Bearer #{llm_api_key}" if llm_api_key.present?
    headers
  end

  def api_base
    case llm_provider
    when 'anthropic'
      'https://api.anthropic.com/v1'
    else
      'https://api.openai.com/v1'
    end
  end

  def llm_provider
    hook.settings['llm_provider'] || 'openai'
  end

  def llm_api_key
    hook.settings['llm_api_key']
  end

  def llm_model
    hook.settings['llm_model'] || 'gpt-4.1-mini'
  end

  def embedding_model
    'text-embedding-3-small'
  end

  def custom_system_prompt
    hook.settings['system_prompt']
  end

  def confidence_threshold
    (hook.settings['confidence_threshold'] || DEFAULT_CONFIDENCE_THRESHOLD).to_f
  end
end
