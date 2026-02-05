# frozen_string_literal: true

class WhatsappTemplateNotificationJob < ApplicationJob
  queue_as :default

  def perform(template_id, event_type)
    template = WhatsappTemplate.find_by(id: template_id)
    return unless template

    account = template.account
    administrators = account.administrators

    administrators.each do |admin|
      AdministratorNotifications::ChannelNotificationsMailer
        .with(account: account)
        .whatsapp_template_status_change(admin, template, event_type)
        .deliver_later
    end
  end
end
