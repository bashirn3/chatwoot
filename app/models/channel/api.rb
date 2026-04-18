# == Schema Information
#
# Table name: channel_api
#
#  id                    :bigint           not null, primary key
#  additional_attributes :jsonb
#  hmac_mandatory        :boolean          default(FALSE)
#  hmac_token            :string
#  identifier            :string
#  webhook_url           :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :integer          not null
#
# Indexes
#
#  index_channel_api_on_hmac_token  (hmac_token) UNIQUE
#  index_channel_api_on_identifier  (identifier) UNIQUE
#

class Channel::Api < ApplicationRecord
  include Channelable

  self.table_name = 'channel_api'
  EDITABLE_ATTRS = [:webhook_url, :hmac_mandatory, { additional_attributes: {} }].freeze

  has_secure_token :identifier
  has_secure_token :hmac_token
  validate :ensure_valid_agent_reply_time_window
  validates :webhook_url, length: { maximum: Limits::URL_LENGTH_LIMIT }

  # When a Baileys-backed API channel is destroyed (inbox deleted via UI,
  # admin cleanup, orphan cleanup from onboarding, etc.), also remove the
  # instance from the WhatsApp bridge framework so the two systems stay
  # in sync and the Wasup instance manager does not accumulate orphans.
  after_destroy_commit :cleanup_whatsapp_bridge_instance, if: :whatsapp_bridge_instance_id

  def name
    'API'
  end

  def whatsapp_bridge_instance_id
    additional_attributes&.dig('whatsapp_bridge_instance_id').presence
  end

  # Which regional framework this instance lives on. Defaults to 'legacy'
  # so any channel missed by the backfill migration still routes correctly
  # to the single-region endpoint we had before the multi-region rollout.
  def whatsapp_bridge_region
    (additional_attributes&.dig('whatsapp_bridge_region').presence || 'legacy').to_s
  end

  def whatsapp_bridge_connection_status
    additional_attributes&.dig('whatsapp_bridge_connection_status').to_s
  end

  def whatsapp_bridge_connected?
    %w[open connected].include?(whatsapp_bridge_connection_status)
  end

  private

  def ensure_valid_agent_reply_time_window
    return if additional_attributes['agent_reply_time_window'].blank?
    return if additional_attributes['agent_reply_time_window'].to_i.positive?

    errors.add(:agent_reply_time_window, 'agent_reply_time_window must be greater than 0')
  end

  def cleanup_whatsapp_bridge_instance
    WhatsappBridge::DeleteInstanceService.new(
      whatsapp_bridge_instance_id,
      region_code: whatsapp_bridge_region
    ).perform
  end
end
