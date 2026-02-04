class WhatsappAccountStatusNotificationJob < ApplicationJob
  queue_as :mailers

  def perform(event_id)
    event = WhatsappAccountStatusEvent.find_by(id: event_id)
    return unless event
    return if event.notification_sent?

    channel = event.channel_whatsapp
    account = event.account
    return unless channel && account

    # Get all administrators for the account
    administrators = account.administrators

    administrators.each do |admin|
      send_notification(admin, event, channel)
    end

    event.update!(notification_sent: true)
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Failed to send status notification for event #{event_id}: #{e.message}"
  end

  private

  def send_notification(admin, event, channel)
    AdministratorNotifications::ChannelNotificationsMailer
      .whatsapp_account_status_alert(admin, event, channel)
      .deliver_later
  end
end
