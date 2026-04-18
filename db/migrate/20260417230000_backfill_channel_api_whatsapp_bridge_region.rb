class BackfillChannelApiWhatsappBridgeRegion < ActiveRecord::Migration[7.0]
  # Stamps every pre-existing WhatsApp bridge channel (created before the
  # multi-region rollout) with `whatsapp_bridge_region: 'legacy'` so that
  # the routing layer picks the correct framework for them. New channels
  # created by the country picker get their actual region at creation time
  # and do not match this filter.
  #
  # Idempotent: re-running is safe; channels that already have a region
  # are skipped.
  def up
    Channel::Api
      .where("additional_attributes ? 'whatsapp_bridge_instance_id'")
      .find_each(batch_size: 200) do |channel|
      attrs = channel.additional_attributes.dup
      next if attrs['whatsapp_bridge_region'].present?

      attrs['whatsapp_bridge_region'] = 'legacy'
      channel.update_column(:additional_attributes, attrs)
    end
  end

  def down
    # No-op: removing the region key would break the multi-region router.
  end
end
