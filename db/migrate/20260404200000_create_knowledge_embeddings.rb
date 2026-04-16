class CreateKnowledgeEmbeddings < ActiveRecord::Migration[7.0]
  def change
    create_table :knowledge_embeddings do |t|
      t.bigint :account_id, null: false
      t.text :content, null: false
      t.vector :embedding, limit: 1536
      t.string :source_type
      t.string :source_url
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :knowledge_embeddings, :account_id
    add_index :knowledge_embeddings, :embedding, using: :ivfflat, name: 'idx_knowledge_embeddings_vector', opclass: :vector_l2_ops
  end
end
