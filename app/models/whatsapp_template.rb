# frozen_string_literal: true

# == Schema Information
#
# Table name: whatsapp_templates
#
#  id                     :bigint           not null, primary key
#  account_id             :bigint           not null
#  channel_whatsapp_id    :bigint
#  clerk_organization_id  :string
#  user_id                :bigint
#  name                   :string           not null
#  language               :string           not null, default: "en"
#  category               :string           not null
#  meta_template_id       :string
#  status                 :string           not null, default: "DRAFT"
#  quality_score          :string
#  rejection_reason       :text
#  header_type            :string
#  header_content         :text
#  header_params          :jsonb
#  body_text              :text             not null
#  body_params            :jsonb
#  footer_text            :text
#  buttons                :jsonb
#  location_latitude      :decimal(10, 7)
#  location_longitude     :decimal(10, 7)
#  location_name          :string
#  location_address       :string
#  submitted_at           :datetime
#  approved_at            :datetime
#  rejected_at            :datetime
#  last_synced_at         :datetime
#  meta_response          :jsonb
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#

class WhatsappTemplate < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :channel_whatsapp, class_name: 'Channel::Whatsapp', optional: true
  belongs_to :user, optional: true

  # Enums
  enum :status, {
    draft: 'DRAFT',
    pending: 'PENDING',
    approved: 'APPROVED',
    rejected: 'REJECTED',
    paused: 'PAUSED',
    disabled: 'DISABLED'
  }, prefix: true

  enum :category, {
    marketing: 'MARKETING',
    utility: 'UTILITY',
    authentication: 'AUTHENTICATION'
  }, prefix: true

  enum :header_type, {
    text: 'TEXT',
    image: 'IMAGE',
    video: 'VIDEO',
    document: 'DOCUMENT',
    location: 'LOCATION'
  }, prefix: :header, allow_nil: true

  # Validations
  validates :name, presence: true,
                   format: { with: /\A[a-z0-9_]+\z/, message: 'must be lowercase letters, numbers, and underscores only' },
                   length: { maximum: 512 }
  validates :name, uniqueness: { scope: [:account_id, :language], message: 'already exists for this account and language' }
  validates :language, presence: true
  validates :category, presence: true
  validates :body_text, presence: true, length: { maximum: 1024 }
  validates :footer_text, length: { maximum: 60 }, allow_blank: true
  validates :header_content, length: { maximum: 60 }, if: :header_text?
  validate :validate_buttons_count
  validate :validate_variables_sequential
  validate :validate_location_data

  # Callbacks
  before_validation :normalize_name
  before_save :extract_variables
  after_update :notify_status_change, if: :saved_change_to_status?

  # Scopes
  scope :by_organization, ->(org_id) { where(clerk_organization_id: org_id) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :by_account, ->(account_id) { where(account_id: account_id) }
  scope :pending_sync, -> { where(status: %w[PENDING APPROVED]).where('last_synced_at < ? OR last_synced_at IS NULL', 1.hour.ago) }
  scope :submittable, -> { where(status: 'DRAFT') }
  scope :active, -> { where(status: 'APPROVED') }

  # Constants
  SUPPORTED_LANGUAGES = {
    'en' => 'English',
    'en_US' => 'English (US)',
    'en_GB' => 'English (UK)',
    'es' => 'Spanish',
    'es_MX' => 'Spanish (Mexico)',
    'es_ES' => 'Spanish (Spain)',
    'pt_BR' => 'Portuguese (Brazil)',
    'pt_PT' => 'Portuguese (Portugal)',
    'fr' => 'French',
    'de' => 'German',
    'it' => 'Italian',
    'ar' => 'Arabic',
    'hi' => 'Hindi',
    'id' => 'Indonesian',
    'ja' => 'Japanese',
    'ko' => 'Korean',
    'nl' => 'Dutch',
    'pl' => 'Polish',
    'ru' => 'Russian',
    'th' => 'Thai',
    'tr' => 'Turkish',
    'vi' => 'Vietnamese',
    'zh_CN' => 'Chinese (Simplified)',
    'zh_TW' => 'Chinese (Traditional)'
  }.freeze

  BUTTON_TYPES = %w[QUICK_REPLY URL PHONE_NUMBER COPY_CODE].freeze
  MAX_BUTTONS = 3
  MAX_QUICK_REPLY_BUTTONS = 3
  MAX_CTA_BUTTONS = 2

  # Instance methods

  # Check if template can be submitted to Meta
  def submittable?
    status_draft? && valid?
  end

  # Check if template can be edited
  def editable?
    status_draft? || status_rejected? || status_pending?
  end

  # Check if template can be reset to draft
  def resettable_to_draft?
    status_pending? || status_rejected? || status_paused?
  end

  # Reset template to draft status for re-editing
  def reset_to_draft!
    return false unless resettable_to_draft?

    update!(
      status: 'DRAFT',
      meta_template_id: nil,
      submitted_at: nil,
      rejection_reason: nil
    )
  end

  # Get variable count in body
  def body_variable_count
    body_text&.scan(/\{\{(\d+)\}\}/)&.flatten&.map(&:to_i)&.max || 0
  end

  # Get variable count in header
  def header_variable_count
    return 0 unless header_text?

    header_content&.scan(/\{\{(\d+)\}\}/)&.flatten&.map(&:to_i)&.max || 0
  end

  # Build Meta API payload for template submission
  def to_meta_payload
    payload = {
      name: name,
      language: language,
      category: category.upcase,
      components: build_components
    }

    # Authentication templates require additional fields
    if category_authentication?
      payload[:message_send_ttl_seconds] = 600 # 10 minute expiry
    end

    payload
  end

  # Build components array for Meta API
  def build_components
    components = []

    # Header component
    components << build_header_component if header_type.present?

    # Body component (required)
    components << build_body_component

    # Footer component
    components << build_footer_component if footer_text.present?

    # Buttons component
    components << build_buttons_component if buttons.present? && buttons.any?

    components.compact
  end

  # Get preview text with sample values
  def preview_body(sample_values = {})
    text = body_text.dup
    (1..body_variable_count).each do |i|
      text.gsub!("{{#{i}}}", sample_values[i.to_s] || sample_values[i] || "[Variable #{i}]")
    end
    text
  end

  # Get preview header with sample values
  def preview_header(sample_values = {})
    return nil unless header_text?

    text = header_content.dup
    (1..header_variable_count).each do |i|
      text.gsub!("{{#{i}}}", sample_values[i.to_s] || sample_values[i] || "[Variable #{i}]")
    end
    text
  end

  # Find template by organization or user (for Clerk migration support)
  def self.find_for_context(account_id:, organization_id: nil, user_id: nil)
    templates = by_account(account_id)

    if organization_id.present?
      templates = templates.by_organization(organization_id)
    elsif user_id.present?
      templates = templates.by_user(user_id)
    end

    templates
  end

  private

  def normalize_name
    self.name = name&.downcase&.gsub(/[^a-z0-9_]/, '_')&.squeeze('_')
  end

  def extract_variables
    # Extract body variables
    body_vars = body_text&.scan(/\{\{(\d+)\}\}/)&.flatten&.map(&:to_i)&.sort&.uniq || []
    self.body_params = body_vars.map { |i| { index: i, example: body_params&.dig(i - 1, 'example') || "Example #{i}" } }

    # Extract header variables if text type
    return unless header_text? && header_content.present?

    header_vars = header_content.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).sort.uniq
    self.header_params = header_vars.map { |i| { index: i, example: header_params&.dig(i - 1, 'example') || "Example #{i}" } }
  end

  def validate_buttons_count
    return if buttons.blank?

    if buttons.length > MAX_BUTTONS
      errors.add(:buttons, "cannot have more than #{MAX_BUTTONS} buttons")
      return
    end

    quick_reply_count = buttons.count { |b| b['type'] == 'QUICK_REPLY' }
    cta_count = buttons.count { |b| %w[URL PHONE_NUMBER].include?(b['type']) }

    errors.add(:buttons, "cannot have more than #{MAX_QUICK_REPLY_BUTTONS} quick reply buttons") if quick_reply_count > MAX_QUICK_REPLY_BUTTONS
    errors.add(:buttons, "cannot have more than #{MAX_CTA_BUTTONS} call-to-action buttons") if cta_count > MAX_CTA_BUTTONS
  end

  def validate_variables_sequential
    # Check body variables are sequential starting from 1
    body_vars = body_text&.scan(/\{\{(\d+)\}\}/)&.flatten&.map(&:to_i)&.sort&.uniq || []
    expected = (1..body_vars.length).to_a

    if body_vars.present? && body_vars != expected
      errors.add(:body_text, 'variables must be sequential starting from {{1}}')
    end

    # Check header variables are sequential
    return unless header_text? && header_content.present?

    header_vars = header_content.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).sort.uniq
    header_expected = (1..header_vars.length).to_a

    return if header_vars.blank? || header_vars == header_expected

    errors.add(:header_content, 'variables must be sequential starting from {{1}}')
  end

  def validate_location_data
    return unless header_location?

    errors.add(:location_latitude, "can't be blank for location header") if location_latitude.blank?
    errors.add(:location_longitude, "can't be blank for location header") if location_longitude.blank?
  end

  def build_header_component
    case header_type
    when 'TEXT'
      {
        type: 'HEADER',
        format: 'TEXT',
        text: header_content,
        example: header_params.present? ? { header_text: header_params.map { |p| p['example'] } } : nil
      }.compact
    when 'IMAGE', 'VIDEO', 'DOCUMENT'
      {
        type: 'HEADER',
        format: header_type,
        example: { header_handle: [header_content] }
      }
    when 'LOCATION'
      {
        type: 'HEADER',
        format: 'LOCATION'
      }
    end
  end

  def build_body_component
    # For AUTHENTICATION templates, Meta auto-generates body text
    # We only need to provide add_security_recommendation flag
    if category_authentication?
      {
        type: 'BODY',
        add_security_recommendation: true
      }
    else
      component = {
        type: 'BODY',
        text: body_text
      }

      if body_params.present? && body_params.any?
        component[:example] = { body_text: [body_params.map { |p| p['example'] }] }
      end

      component
    end
  end

  def build_footer_component
    {
      type: 'FOOTER',
      text: footer_text
    }
  end

  def build_buttons_component
    {
      type: 'BUTTONS',
      buttons: buttons.map { |btn| build_button(btn) }
    }
  end

  def build_button(btn)
    case btn['type']
    when 'QUICK_REPLY'
      { type: 'QUICK_REPLY', text: btn['text'] }
    when 'URL'
      button = { type: 'URL', text: btn['text'], url: btn['url'] }
      button[:example] = [btn['url_example']] if btn['url']&.include?('{{1}}') && btn['url_example'].present?
      button
    when 'PHONE_NUMBER'
      { type: 'PHONE_NUMBER', text: btn['text'], phone_number: btn['phone_number'] }
    when 'COPY_CODE'
      # For authentication templates, OTP button with copy code
      { type: 'OTP', otp_type: 'COPY_CODE', text: btn['text'] || 'Copy code' }
    when 'OTP'
      # Generic OTP button
      { type: 'OTP', otp_type: btn['otp_type'] || 'COPY_CODE', text: btn['text'] || 'Copy code' }
    end
  end

  def notify_status_change
    # Send notification about status change
    return unless saved_change_to_status?

    case status
    when 'APPROVED'
      self.approved_at = Time.current
      WhatsappTemplateNotificationJob.perform_later(id, 'approved')
    when 'REJECTED'
      self.rejected_at = Time.current
      WhatsappTemplateNotificationJob.perform_later(id, 'rejected')
    when 'PAUSED', 'DISABLED'
      WhatsappTemplateNotificationJob.perform_later(id, 'paused')
    end
  end
end
