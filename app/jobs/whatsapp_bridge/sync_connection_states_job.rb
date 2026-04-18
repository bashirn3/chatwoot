module WhatsappBridge
  # Runs every few minutes via sidekiq-cron. Iterates every `Channel::Api`
  # that has a `whatsapp_bridge_instance_id` (i.e. every Baileys-backed
  # WhatsApp inbox across all accounts) and syncs its connection state
  # with the framework, firing disconnect alert emails when needed.
  class SyncConnectionStatesJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform
      return if ENV.fetch('WHATSAPP_BRIDGE_URL', nil).blank?

      Channel::Api
        .where("additional_attributes ? 'whatsapp_bridge_instance_id'")
        .find_each(batch_size: 100) do |channel|
        SyncConnectionStateService.new(channel).perform
      rescue StandardError => e
        Rails.logger.warn("[WhatsappBridge] sync failed for channel #{channel.id}: #{e.message}")
      end
    end
  end
end
