class AddAccountStatusToChannelWhatsapp < ActiveRecord::Migration[7.0]
  def change
    # Add account status tracking fields to channel_whatsapp (only if columns don't exist)
    add_column :channel_whatsapp, :account_status, :string, default: 'ACTIVE' unless column_exists?(:channel_whatsapp, :account_status)
    add_column :channel_whatsapp, :quality_rating, :string unless column_exists?(:channel_whatsapp, :quality_rating)
    add_column :channel_whatsapp, :messaging_limit_tier, :string unless column_exists?(:channel_whatsapp, :messaging_limit_tier)
    add_column :channel_whatsapp, :current_throughput, :integer unless column_exists?(:channel_whatsapp, :current_throughput)
    add_column :channel_whatsapp, :account_status_last_synced_at, :datetime unless column_exists?(:channel_whatsapp, :account_status_last_synced_at)
    add_column :channel_whatsapp, :business_verification_status, :string unless column_exists?(:channel_whatsapp, :business_verification_status)
    add_column :channel_whatsapp, :display_name_status, :string unless column_exists?(:channel_whatsapp, :display_name_status)
    add_column :channel_whatsapp, :account_review_status, :string unless column_exists?(:channel_whatsapp, :account_review_status)
    
    # Store violation and restriction details
    add_column :channel_whatsapp, :violation_info, :jsonb, default: {} unless column_exists?(:channel_whatsapp, :violation_info)
    add_column :channel_whatsapp, :restrictions, :jsonb, default: [] unless column_exists?(:channel_whatsapp, :restrictions)
    
    # Indexes for quick filtering (only if they don't exist)
    add_index :channel_whatsapp, :account_status unless index_exists?(:channel_whatsapp, :account_status)
    add_index :channel_whatsapp, :quality_rating unless index_exists?(:channel_whatsapp, :quality_rating)
    
    # Create a separate table for status change history/events (only if doesn't exist)
    return if table_exists?(:whatsapp_account_status_events)
    
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
    
    add_index :whatsapp_account_status_events, [:channel_whatsapp_id, :event_type], name: 'idx_wa_status_events_channel_type' unless index_exists?(:whatsapp_account_status_events, [:channel_whatsapp_id, :event_type])
    add_index :whatsapp_account_status_events, [:account_id, :created_at], name: 'idx_wa_status_events_account_time' unless index_exists?(:whatsapp_account_status_events, [:account_id, :created_at])
    add_index :whatsapp_account_status_events, :notification_sent unless index_exists?(:whatsapp_account_status_events, :notification_sent)
  end
end
