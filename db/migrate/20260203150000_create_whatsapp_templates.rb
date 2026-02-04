# frozen_string_literal: true

class CreateWhatsappTemplates < ActiveRecord::Migration[7.0]
  def change
    create_table :whatsapp_templates do |t|
      # Account association (existing Chatwoot pattern)
      t.references :account, null: false, foreign_key: true, index: true
      
      # Channel association (which WhatsApp channel this template belongs to)
      t.references :channel_whatsapp, foreign_key: { to_table: :channel_whatsapp }, index: true
      
      # Organization support (for Clerk integration)
      t.string :clerk_organization_id, index: true
      
      # User who created it (fallback for non-Clerk or individual templates)
      t.references :user, foreign_key: true, index: true
      
      # Template identification
      t.string :name, null: false
      t.string :language, null: false, default: 'en'
      t.string :category, null: false # MARKETING, UTILITY, AUTHENTICATION
      
      # Meta API response fields
      t.string :meta_template_id # ID returned from Meta after submission
      t.string :status, null: false, default: 'DRAFT' # DRAFT, PENDING, APPROVED, REJECTED, PAUSED, DISABLED
      t.string :quality_score # GREEN, YELLOW, RED
      t.text :rejection_reason
      
      # Template content - Header
      t.string :header_type # TEXT, IMAGE, VIDEO, DOCUMENT, LOCATION
      t.text :header_content # Text content or media URL
      t.jsonb :header_params, default: {} # For variables in header
      
      # Template content - Body (required)
      t.text :body_text, null: false
      t.jsonb :body_params, default: [] # Array of variable examples
      
      # Template content - Footer (optional)
      t.text :footer_text
      
      # Template content - Buttons (optional)
      t.jsonb :buttons, default: [] # Array of button objects
      
      # Location data (if header_type is LOCATION)
      t.decimal :location_latitude, precision: 10, scale: 7
      t.decimal :location_longitude, precision: 10, scale: 7
      t.string :location_name
      t.string :location_address
      
      # Timestamps for tracking
      t.datetime :submitted_at
      t.datetime :approved_at
      t.datetime :rejected_at
      t.datetime :last_synced_at
      
      # Store full Meta API response for debugging
      t.jsonb :meta_response, default: {}
      
      t.timestamps
    end
    
    # Ensure unique template names per account/language combination
    add_index :whatsapp_templates, [:account_id, :name, :language], unique: true, name: 'idx_whatsapp_templates_unique_name'
    
    # Index for organization-based queries (Clerk)
    add_index :whatsapp_templates, [:clerk_organization_id, :status], name: 'idx_whatsapp_templates_org_status'
    
    # Index for finding templates by status for sync jobs
    add_index :whatsapp_templates, [:status, :last_synced_at], name: 'idx_whatsapp_templates_sync'
  end
end
