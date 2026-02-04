class AddAccountStatusToChannelWhatsapp < ActiveRecord::Migration[7.0]
  def change
    # Add account status tracking fields to channel_whatsapp
    add_column :channel_whatsapp, :account_status, :string, default: 'ACTIVE'
    add_column :channel_whatsapp, :quality_rating, :string # GREEN, YELLOW, RED
    add_column :channel_whatsapp, :messaging_limit_tier, :string # TIER_50, TIER_250, TIER_1K, TIER_10K, TIER_100K, UNLIMITED
    add_column :channel_whatsapp, :current_throughput, :integer # messages per second
    add_column :channel_whatsapp, :account_status_last_synced_at, :datetime
    add_column :channel_whatsapp, :business_verification_status, :string # verified, unverified, pending
    add_column :channel_whatsapp, :display_name_status, :string # APPROVED, PENDING, REJECTED
    add_column :channel_whatsapp, :account_review_status, :string # APPROVED, PENDING, REJECTED
    
    # Store violation and restriction details
    add_column :channel_whatsapp, :violation_info, :jsonb, default: {}
    add_column :channel_whatsapp, :restrictions, :jsonb, default: []
    
    # Indexes for quick filtering
    add_index :channel_whatsapp, :account_status
    add_index :channel_whatsapp, :quality_rating
    
    # Create a separate table for status change history/events
    create_table :whatsapp_account_status_events do |t|
      t.references :channel_whatsapp, null: false, foreign_key: { to_table: :channel_whatsapp }
      t.references :account, null: false, foreign_key: true
      t.string :event_type, null: false # STATUS_CHANGE, QUALITY_CHANGE, VIOLATION, RESTRICTION, MESSAGING_LIMIT_CHANGE
      t.string :previous_value
      t.string :new_value
      t.jsonb :event_data, default: {}
      t.string :source # API_SYNC, WEBHOOK, MANUAL
      t.datetime :event_timestamp
      t.boolean :notification_sent, default: false
      t.timestamps
    end
    
    add_index :whatsapp_account_status_events, [:channel_whatsapp_id, :event_type], name: 'idx_wa_status_events_channel_type'
    add_index :whatsapp_account_status_events, [:account_id, :created_at], name: 'idx_wa_status_events_account_time'
    add_index :whatsapp_account_status_events, :notification_sent
  end
end
