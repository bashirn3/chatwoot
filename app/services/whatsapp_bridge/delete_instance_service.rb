module WhatsappBridge
  # Deletes a single instance from a regional WhatsApp bridge framework.
  # Used whenever a Chatwoot inbox tied to a bridge instance is destroyed
  # (Settings UI delete, onboarding skip, admin cleanup, etc.) so the
  # framework side stays in sync and no orphan instances remain.
  #
  # Accepts either a region code or falls back to 'legacy' to preserve
  # backward-compat for instances provisioned before the multi-region
  # rollout (all existing channels are backfilled to region='legacy').
  class DeleteInstanceService
    def initialize(instance_id, region_code: 'legacy')
      @instance_id = instance_id.to_s
      @region_code = region_code.presence || 'legacy'
    end

    def perform
      return if @instance_id.blank?

      client = RegionalClient.new(@region_code)
      return unless client.configured?

      client.delete("/api/instances/#{@instance_id}")
    rescue StandardError => e
      Rails.logger.warn("[WhatsappBridge] #{@region_code} delete failed for #{@instance_id}: #{e.class}")
      nil
    end
  end
end
