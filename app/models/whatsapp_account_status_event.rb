# == Schema Information
#
# Table name: whatsapp_account_status_events
#
#  id                   :bigint           not null, primary key
#  channel_whatsapp_id  :bigint           not null
#  account_id           :bigint           not null
#  event_type           :string           not null
#  previous_value       :string
#  new_value            :string
#  event_data           :jsonb
#  source               :string
#  event_timestamp      :datetime
#  notification_sent    :boolean          default(FALSE)
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#

class WhatsappAccountStatusEvent < ApplicationRecord
  belongs_to :channel_whatsapp, class_name: 'Channel::Whatsapp'
  belongs_to :account

  # Event types
  EVENT_TYPES = %w[
    STATUS_CHANGE
    QUALITY_CHANGE
    VIOLATION
    RESTRICTION
    MESSAGING_LIMIT_CHANGE
    THROUGHPUT_CHANGE
    VERIFICATION_CHANGE
    DISPLAY_NAME_CHANGE
    ACCOUNT_REVIEW_CHANGE
  ].freeze

  # Source types
  SOURCES = %w[API_SYNC WEBHOOK MANUAL].freeze

  # Critical events that require immediate notification
  CRITICAL_EVENTS = %w[STATUS_CHANGE VIOLATION RESTRICTION].freeze

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :source, inclusion: { in: SOURCES }, allow_nil: true

  scope :critical, -> { where(event_type: CRITICAL_EVENTS) }
  scope :pending_notification, -> { where(notification_sent: false) }
  scope :recent, -> { where('created_at > ?', 24.hours.ago) }
  scope :by_channel, ->(channel_id) { where(channel_whatsapp_id: channel_id) }

  after_create :schedule_notification, if: :should_notify?

  def critical?
    CRITICAL_EVENTS.include?(event_type)
  end

  def severity
    case event_type
    when 'STATUS_CHANGE'
      new_value.in?(%w[BANNED RESTRICTED FLAGGED]) ? :critical : :info
    when 'VIOLATION', 'RESTRICTION'
      :critical
    when 'QUALITY_CHANGE'
      new_value == 'RED' ? :warning : :info
    when 'MESSAGING_LIMIT_CHANGE'
      :info
    else
      :info
    end
  end

  def human_readable_message
    case event_type
    when 'STATUS_CHANGE'
      status_change_message
    when 'QUALITY_CHANGE'
      "Quality rating changed from #{previous_value || 'N/A'} to #{new_value}"
    when 'VIOLATION'
      "Policy violation detected: #{event_data['violation_type'] || 'Unknown'}"
    when 'RESTRICTION'
      "Account restriction applied: #{event_data['restriction_type'] || 'Unknown'}"
    when 'MESSAGING_LIMIT_CHANGE'
      "Messaging limit changed from #{previous_value || 'N/A'} to #{new_value}"
    when 'THROUGHPUT_CHANGE'
      "Throughput changed from #{previous_value || 'N/A'} to #{new_value} mps"
    when 'VERIFICATION_CHANGE'
      "Business verification status changed to #{new_value}"
    when 'DISPLAY_NAME_CHANGE'
      "Display name status changed to #{new_value}"
    when 'ACCOUNT_REVIEW_CHANGE'
      "Account review status changed to #{new_value}"
    else
      "#{event_type.humanize}: #{new_value}"
    end
  end

  private

  def status_change_message
    case new_value
    when 'BANNED'
      'Your WhatsApp Business Account has been BANNED. Please review Meta\'s policies and request a review if you believe this is an error.'
    when 'RESTRICTED'
      'Your WhatsApp Business Account has been RESTRICTED. Some features may be limited.'
    when 'FLAGGED'
      'Your WhatsApp Business Account has been FLAGGED for review. Please ensure compliance with Meta\'s policies.'
    when 'ACTIVE'
      if previous_value.present? && previous_value != 'ACTIVE'
        "Your WhatsApp Business Account has been restored to ACTIVE status."
      else
        'WhatsApp Business Account status is ACTIVE.'
      end
    else
      "Account status changed from #{previous_value || 'N/A'} to #{new_value}"
    end
  end

  def should_notify?
    critical? || severity == :warning
  end

  def schedule_notification
    WhatsappAccountStatusNotificationJob.perform_later(id)
  end
end
