# frozen_string_literal: true

class Whatsapp::TemplatesStatusSyncJob < ApplicationJob
  queue_as :low

  def perform
    # Find all templates that need syncing (pending/approved status, not synced in last hour)
    templates_to_sync = WhatsappTemplate.pending_sync

    templates_to_sync.find_each do |template|
      sync_template(template)
    rescue StandardError => e
      Rails.logger.error("[WhatsApp Template Sync] Error syncing template #{template.id}: #{e.message}")
    end
  end

  private

  def sync_template(template)
    return if template.meta_template_id.blank?

    service = Whatsapp::TemplateManagementService.new(template: template)
    service.sync_status
  end
end
