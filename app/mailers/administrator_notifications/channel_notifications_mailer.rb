class AdministratorNotifications::ChannelNotificationsMailer < AdministratorNotifications::BaseMailer
  def facebook_disconnect(inbox)
    subject = 'Your Facebook page connection has expired'
    send_notification(subject, action_url: inbox_url(inbox))
  end

  def instagram_disconnect(inbox)
    subject = 'Your Instagram connection has expired'
    send_notification(subject, action_url: inbox_url(inbox))
  end

  def tiktok_disconnect(inbox)
    subject = 'Your TikTok connection has expired'
    send_notification(subject, action_url: inbox_url(inbox))
  end

  def whatsapp_disconnect(inbox)
    subject = 'Your Whatsapp connection has expired'
    send_notification(subject, action_url: inbox_url(inbox))
  end

  def email_disconnect(inbox)
    subject = 'Your email inbox has been disconnected. Please update the credentials for SMTP/IMAP'
    send_notification(subject, action_url: inbox_url(inbox))
  end

  def whatsapp_template_status_change(user, template, event_type)
    return unless user.email.present?

    @user = user
    @template = template
    @event_type = event_type
    @account = @template.account

    subject = case event_type
              when 'approved'
                "✅ WhatsApp Template '#{template.name}' has been approved"
              when 'rejected'
                "❌ WhatsApp Template '#{template.name}' was rejected"
              when 'paused'
                "⚠️ WhatsApp Template '#{template.name}' has been paused"
              else
                "WhatsApp Template '#{template.name}' status updated"
              end

    @action_url = "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{@account.id}/settings/whatsapp-templates"

    mail(
      to: user.email,
      subject: subject
    ) do |format|
      format.html { render 'whatsapp_template_status_change' }
    end
  end

  def whatsapp_account_status_alert(user, event, channel)
    return unless user.email.present?

    @user = user
    @event = event
    @channel = channel
    @account = event.account
    @inbox = channel.inbox

    subject = build_account_status_subject(event)
    @action_url = "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{@account.id}/settings/inboxes/#{@inbox&.id}"

    mail(
      to: user.email,
      subject: subject
    ) do |format|
      format.html { render 'whatsapp_account_status_alert' }
    end
  end

  private

  def build_account_status_subject(event)
    case event.event_type
    when 'STATUS_CHANGE'
      case event.new_value
      when 'BANNED'
        "🚫 URGENT: Your WhatsApp Business Account has been BANNED"
      when 'RESTRICTED'
        "⚠️ WARNING: Your WhatsApp Business Account has been RESTRICTED"
      when 'FLAGGED'
        "⚠️ NOTICE: Your WhatsApp Business Account has been FLAGGED"
      when 'ACTIVE'
        "✅ Your WhatsApp Business Account has been restored"
      else
        "WhatsApp Business Account status changed to #{event.new_value}"
      end
    when 'VIOLATION'
      "🚨 ALERT: Policy violation detected on your WhatsApp Business Account"
    when 'RESTRICTION'
      "⚠️ WARNING: Restriction applied to your WhatsApp Business Account"
    when 'QUALITY_CHANGE'
      if event.new_value == 'RED'
        "⚠️ WARNING: WhatsApp quality rating dropped to RED"
      else
        "WhatsApp quality rating changed to #{event.new_value}"
      end
    else
      "WhatsApp Business Account update: #{event.event_type.humanize}"
    end
  end
end
