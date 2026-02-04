class Whatsapp::AccountStatusSyncJob < ApplicationJob
  queue_as :low

  # Sync account status for all WhatsApp Cloud channels
  # Run this periodically (e.g., every 6 hours)
  def perform(channel_id = nil)
    if channel_id
      sync_single_channel(channel_id)
    else
      sync_all_channels
    end
  end

  private

  def sync_single_channel(channel_id)
    channel = Channel::Whatsapp.find_by(id: channel_id)
    return unless channel&.provider == 'whatsapp_cloud'

    Whatsapp::AccountStatusSyncService.new(whatsapp_channel: channel).perform
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Status sync failed for channel #{channel_id}: #{e.message}"
  end

  def sync_all_channels
    Channel::Whatsapp.where(provider: 'whatsapp_cloud').find_each do |channel|
      # Stagger the sync to avoid rate limiting
      Whatsapp::AccountStatusSyncJob.set(wait: rand(1..60).seconds).perform_later(channel.id)
    end
  end
end
