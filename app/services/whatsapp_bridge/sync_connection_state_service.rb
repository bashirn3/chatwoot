module WhatsappBridge
  # Per-channel sync: asks the regional WhatsApp bridge framework for the
  # current connection state of the linked instance, persists the result
  # on the channel, and fires a disconnect alert email (admins + inbox
  # members) when we detect a transition from connected → disconnected.
  #
  # The region is read from the channel itself so this works identically
  # for legacy channels (region='legacy') and regional channels.
  #
  # Persisted keys on `Channel::Api#additional_attributes`:
  #   - whatsapp_bridge_connection_status       last reported framework state
  #   - whatsapp_bridge_last_checked_at         ISO8601 of last sync attempt
  #   - whatsapp_bridge_last_disconnected_at    ISO8601 of last disconnect event
  #   - whatsapp_bridge_last_alert_at           ISO8601 of last alert sent (for cooldown)
  class SyncConnectionStateService
    CONNECTED_STATES = %w[open connected].freeze
    DISCONNECTED_STATES = %w[close closed logged_out logged-out disconnected].freeze
    ALERT_COOLDOWN = 30.minutes

    def initialize(channel)
      @channel = channel
      @instance_id = channel.whatsapp_bridge_instance_id
      @region_code = channel.whatsapp_bridge_region
    end

    def perform
      return if @instance_id.blank?

      client = RegionalClient.new(@region_code)
      return unless client.configured?

      new_state = fetch_state(client)
      return if new_state.blank?

      previous_state = @channel.additional_attributes['whatsapp_bridge_connection_status']
      persist_state(new_state)

      return unless transitioned_to_disconnected?(previous_state, new_state)
      return if alert_on_cooldown?

      dispatch_disconnect_alert(new_state)
      persist_alert_timestamps
    end

    private

    def fetch_state(client)
      response = client.get("/api/instances/#{@instance_id}/connection")
      return nil if response['error'].present?

      # Framework variants seen in the wild: { connection: 'open' }, { state: '...' }, { status: '...' }
      state = response['connection'] || response['state'] || response['status']
      state&.to_s&.downcase
    end

    def persist_state(new_state)
      attrs = @channel.additional_attributes.dup
      attrs['whatsapp_bridge_connection_status'] = new_state
      attrs['whatsapp_bridge_last_checked_at'] = Time.current.iso8601
      @channel.update_column(:additional_attributes, attrs)
    end

    def transitioned_to_disconnected?(previous, current)
      return false unless DISCONNECTED_STATES.include?(current)
      # First-ever sync on an already-disconnected instance → don't spam an alert
      return false if previous.nil?
      # Only alert if we were previously in a "good" state.
      CONNECTED_STATES.include?(previous)
    end

    def alert_on_cooldown?
      last = @channel.additional_attributes['whatsapp_bridge_last_alert_at']
      return false if last.blank?

      Time.parse(last) > ALERT_COOLDOWN.ago
    rescue ArgumentError
      false
    end

    def dispatch_disconnect_alert(current_state)
      inbox = @channel.inbox
      return if inbox.blank?

      account = inbox.account
      AdministratorNotifications::ChannelNotificationsMailer
        .with(account: account)
        .whatsapp_bridge_disconnect(inbox, current_state)
        .deliver_later
    end

    def persist_alert_timestamps
      now = Time.current.iso8601
      attrs = @channel.additional_attributes.dup
      attrs['whatsapp_bridge_last_alert_at'] = now
      attrs['whatsapp_bridge_last_disconnected_at'] = now
      @channel.update_column(:additional_attributes, attrs)
    end
  end
end
