# == Schema Information
#
# Table name: channel_whatsapp
#
#  id                             :bigint           not null, primary key
#  message_templates              :jsonb
#  message_templates_last_updated :datetime
#  phone_number                   :string           not null
#  provider                       :string           default("default")
#  provider_config                :jsonb
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :integer          not null
#
# Indexes
#
#  index_channel_whatsapp_on_phone_number  (phone_number) UNIQUE
#

class Channel::Whatsapp < ApplicationRecord
  include Channelable
  include Reauthorizable

  self.table_name = 'channel_whatsapp'
  EDITABLE_ATTRS = [:phone_number, :provider, { provider_config: {} }].freeze

  # default at the moment is 360dialog lets change later.
  PROVIDERS = %w[default whatsapp_cloud].freeze

  # Account status values from Meta
  ACCOUNT_STATUSES = %w[ACTIVE RESTRICTED BANNED FLAGGED PENDING_DELETION DISABLED].freeze
  QUALITY_RATINGS = %w[GREEN YELLOW RED].freeze
  MESSAGING_LIMIT_TIERS = %w[TIER_50 TIER_250 TIER_1K TIER_10K TIER_100K UNLIMITED].freeze

  before_validation :ensure_webhook_verify_token

  validates :provider, inclusion: { in: PROVIDERS }
  validates :phone_number, presence: true, uniqueness: true
  validates :account_status, inclusion: { in: ACCOUNT_STATUSES }, allow_nil: true
  validates :quality_rating, inclusion: { in: QUALITY_RATINGS }, allow_nil: true
  validate :validate_provider_config

  has_many :status_events, class_name: 'WhatsappAccountStatusEvent', foreign_key: 'channel_whatsapp_id', dependent: :destroy

  after_create :sync_templates
  before_destroy :teardown_webhooks
  after_commit :setup_webhooks, on: :create, if: :should_auto_setup_webhooks?

  # Scopes for filtering by status
  scope :active, -> { where(account_status: 'ACTIVE') }
  scope :restricted, -> { where(account_status: 'RESTRICTED') }
  scope :banned, -> { where(account_status: 'BANNED') }
  scope :flagged, -> { where(account_status: 'FLAGGED') }
  scope :with_issues, -> { where(account_status: %w[RESTRICTED BANNED FLAGGED]) }
  scope :low_quality, -> { where(quality_rating: %w[YELLOW RED]) }
  scope :needs_attention, -> { where(account_status: %w[RESTRICTED BANNED FLAGGED]).or(where(quality_rating: 'RED')) }

  def name
    'Whatsapp'
  end

  def provider_service
    if provider == 'whatsapp_cloud'
      Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: self)
    else
      Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: self)
    end
  end

  def mark_message_templates_updated
    # rubocop:disable Rails/SkipsModelValidations
    update_column(:message_templates_last_updated, Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  delegate :send_message, to: :provider_service
  delegate :send_template, to: :provider_service
  delegate :sync_templates, to: :provider_service
  delegate :media_url, to: :provider_service
  delegate :api_headers, to: :provider_service

  # Status helper methods
  def active?
    account_status == 'ACTIVE'
  end

  def banned?
    account_status == 'BANNED'
  end

  def restricted?
    account_status == 'RESTRICTED'
  end

  def flagged?
    account_status == 'FLAGGED'
  end

  def has_issues?
    %w[RESTRICTED BANNED FLAGGED].include?(account_status)
  end

  def quality_ok?
    quality_rating.nil? || quality_rating == 'GREEN'
  end

  def needs_attention?
    has_issues? || quality_rating == 'RED'
  end

  def status_summary
    {
      account_status: account_status,
      quality_rating: quality_rating,
      messaging_limit_tier: messaging_limit_tier,
      current_throughput: current_throughput,
      business_verification_status: business_verification_status,
      display_name_status: display_name_status,
      account_review_status: account_review_status,
      violations: violation_info,
      restrictions: restrictions,
      last_synced_at: account_status_last_synced_at
    }
  end

  def update_status(new_status, source: 'API_SYNC')
    return if new_status == account_status

    old_status = account_status
    update!(
      account_status: new_status,
      account_status_last_synced_at: Time.current
    )

    record_status_event(
      event_type: 'STATUS_CHANGE',
      previous_value: old_status,
      new_value: new_status,
      source: source
    )
  end

  def update_quality_rating(new_rating, source: 'API_SYNC')
    return if new_rating == quality_rating

    old_rating = quality_rating
    update!(
      quality_rating: new_rating,
      account_status_last_synced_at: Time.current
    )

    record_status_event(
      event_type: 'QUALITY_CHANGE',
      previous_value: old_rating,
      new_value: new_rating,
      source: source
    )
  end

  def record_violation(violation_type:, details: {}, source: 'WEBHOOK')
    current_violations = violation_info || {}
    current_violations[violation_type] = {
      detected_at: Time.current,
      details: details
    }
    update!(violation_info: current_violations)

    record_status_event(
      event_type: 'VIOLATION',
      new_value: violation_type,
      event_data: details,
      source: source
    )
  end

  def record_restriction(restriction_type:, details: {}, source: 'WEBHOOK')
    current_restrictions = restrictions || []
    current_restrictions << {
      type: restriction_type,
      applied_at: Time.current,
      details: details
    }
    update!(restrictions: current_restrictions)

    record_status_event(
      event_type: 'RESTRICTION',
      new_value: restriction_type,
      event_data: details,
      source: source
    )
  end

  def sync_account_status
    return unless provider == 'whatsapp_cloud'

    Whatsapp::AccountStatusSyncService.new(whatsapp_channel: self).perform
  end

  def recent_events(limit: 10)
    status_events.order(created_at: :desc).limit(limit)
  end

  def setup_webhooks
    perform_webhook_setup
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Webhook setup failed: #{e.message}"
    # Don't mark newly created channels as "connection expired" when webhook setup fails
    # (e.g. permissions, wrong WABA ID). They can still send messages; inbound may need reconnect later.
    prompt_reauthorization! unless created_at > 2.minutes.ago
  end

  private

  def ensure_webhook_verify_token
    provider_config['webhook_verify_token'] ||= SecureRandom.hex(16) if provider == 'whatsapp_cloud'
  end

  def validate_provider_config
    errors.add(:provider_config, 'Invalid Credentials') unless provider_service.validate_provider_config?
  end

  def perform_webhook_setup
    business_account_id = provider_config['business_account_id']
    api_key = provider_config['api_key']

    Whatsapp::WebhookSetupService.new(self, business_account_id, api_key).perform
  end

  def teardown_webhooks
    Whatsapp::WebhookTeardownService.new(self).perform
  end

  def should_auto_setup_webhooks?
    # Only auto-setup webhooks for whatsapp_cloud provider with manual setup
    # Embedded signup calls setup_webhooks explicitly in EmbeddedSignupService
    provider == 'whatsapp_cloud' && provider_config['source'] != 'embedded_signup'
  end

  def record_status_event(event_type:, previous_value: nil, new_value: nil, event_data: {}, source: 'API_SYNC')
    status_events.create!(
      account: inbox&.account,
      event_type: event_type,
      previous_value: previous_value,
      new_value: new_value,
      event_data: event_data,
      source: source,
      event_timestamp: Time.current
    )
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Failed to record status event: #{e.message}"
  end
end
