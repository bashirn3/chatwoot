namespace :rag do
  desc 'Ingest help center articles into knowledge_embeddings for RAG bot'
  task ingest: :environment do
    account_id = ENV.fetch('ACCOUNT_ID', nil)
    api_key = ENV.fetch('OPENAI_API_KEY') { InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value }

    abort 'ACCOUNT_ID is required. Usage: rake rag:ingest ACCOUNT_ID=1' unless account_id
    abort 'OPENAI_API_KEY or CAPTAIN_OPEN_AI_API_KEY must be set' unless api_key

    account = Account.find(account_id)
    articles = account.articles.where(status: :published)

    puts "Found #{articles.count} published articles for account #{account_id}"

    articles.find_each do |article|
      content = "#{article.title}\n\n#{article.content&.gsub(/<[^>]+>/, '')}"
      next if content.strip.length < 20

      embedding = fetch_embedding(content, api_key)
      next unless embedding

      KnowledgeEmbedding.find_or_initialize_by(
        account_id: account.id,
        source_type: 'Article',
        source_url: "article://#{article.id}"
      ).update!(
        content: content.truncate(8000),
        embedding: embedding,
        metadata: { article_id: article.id, title: article.title }
      )

      puts "  Embedded: #{article.title}"
    end

    puts 'Done.'
  end
end

def fetch_embedding(text, api_key)
  response = HTTParty.post(
    'https://api.openai.com/v1/embeddings',
    headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{api_key}" },
    body: { model: 'text-embedding-3-small', input: text.truncate(8000) }.to_json,
    timeout: 30
  )

  return nil unless response.success?

  response.parsed_response.dig('data', 0, 'embedding')
rescue StandardError => e
  puts "  Error embedding: #{e.message}"
  nil
end
