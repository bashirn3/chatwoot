class WhatsappBridge::IncomingMessageService
  pattr_initialize [:inbox!, :params!]

  def perform
    phone = params[:from_phone].to_s.gsub(/\D/, '')
    return if phone.blank?

    contact_inbox = if group?
                      find_or_create_group_contact(phone)
                    else
                      find_or_create_contact(phone)
                    end

    conversation = find_or_create_conversation(contact_inbox)

    message = conversation.messages.create!(
      account_id: account.id,
      inbox_id: inbox.id,
      message_type: :incoming,
      content: params[:message].presence || '',
      sender: contact_inbox.contact,
      source_id: params[:message_id]
    )

    process_media_attachment(message) if params[:media_url].present?
    message
  end

  private

  delegate :account, to: :inbox

  def group?
    ActiveModel::Type::Boolean.new.cast(params[:is_group])
  end

  def find_or_create_group_contact(group_id)
    display_name = params[:group_name].presence || "Group #{group_id[-6..]}"
    contact = account.contacts.find_by(identifier: group_id)
    if contact
      contact.update!(name: display_name) if params[:group_name].present? && contact.name != display_name
    else
      contact = account.contacts.create!(name: display_name, identifier: group_id)
    end

    contact_inbox = ContactInbox.find_by(contact: contact, inbox: inbox)
    contact_inbox || ContactInbox.create!(contact: contact, inbox: inbox, source_id: group_id)
  end

  def find_or_create_contact(phone)
    display_name = params[:sender_name].presence || phone
    formatted_phone = "+#{phone}"
    contact = account.contacts.find_by(phone_number: formatted_phone)
    contact ||= account.contacts.create!(name: display_name, phone_number: formatted_phone)
    contact.update!(name: display_name) if params[:sender_name].present? && contact.name == contact.phone_number&.delete('+')

    contact_inbox = ContactInbox.find_by(contact: contact, inbox: inbox)
    contact_inbox || ContactInbox.create!(contact: contact, inbox: inbox, source_id: phone)
  end

  def find_or_create_conversation(contact_inbox)
    conversation = contact_inbox.conversations.where.not(status: :resolved).order(created_at: :desc).first
    return conversation if conversation

    Conversation.create!(
      account_id: account.id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id
    )
  end

  MEDIA_TYPE_MAP = {
    'sticker' => :image, 'image' => :image, 'photo' => :image,
    'video' => :video, 'audio' => :audio, 'voice' => :audio,
    'document' => :file, 'file' => :file
  }.freeze

  def process_media_attachment(message)
    file = Down.download(params[:media_url])
    message.attachments.create!(
      account_id: message.account_id,
      file_type: MEDIA_TYPE_MAP[params[:media_type]] || :file,
      file: {
        io: file,
        filename: params[:file_name] || File.basename(params[:media_url]),
        content_type: params[:mime_type] || 'application/octet-stream'
      }
    )
  rescue StandardError => e
    Rails.logger.warn "Failed to download WhatsApp media: #{e.message}"
  end
end
