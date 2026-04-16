class KnowledgeEmbedding < ApplicationRecord
  has_neighbors :embedding

  belongs_to :account

  validates :content, presence: true
  validates :account_id, presence: true

  scope :for_account, ->(account_id) { where(account_id: account_id) }
end
