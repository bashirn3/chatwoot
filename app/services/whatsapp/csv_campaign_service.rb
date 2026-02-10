require 'csv'

class Whatsapp::CsvCampaignService
  attr_reader :account, :inbox, :channel, :csv_rows, :template_params_base,
              :phone_column, :name_column, :variable_mappings, :delay_ms, :template_body_text

  def initialize(params)
    @account = params[:account]
    @inbox = params[:inbox]
    @channel = inbox.channel
    @csv_rows = params[:csv_rows]
    @template_params_base = params[:template_params_base]
    @phone_column = params[:phone_column]
    @name_column = params[:name_column]
    @variable_mappings = params[:variable_mappings]
    @delay_ms = params[:delay_ms] || 1000
    @sender = params[:sender]
    @template_body_text = params[:template_body_text] || ''
  end

  def each_row
    counters = { sent: 0, failed: 0, skipped: 0 }
    total = csv_rows.length

    csv_rows.each_with_index do |row, idx|
      event = process_row(row, idx, total, counters)
      yield event
      sleep(delay_ms.to_f / 1000) if delay_ms.to_i.positive?
    end

    yield({ type: 'done', sent: counters[:sent], failed: counters[:failed], skipped: counters[:skipped], total: total })
  end

  private

  def process_row(row, idx, total, counters)
    phone_raw = row[phone_column].to_s.strip

    if phone_raw.blank?
      counters[:skipped] += 1
      return row_event(counters, index: idx, total: total, phone: 'EMPTY', status: 'skipped', detail: 'No phone')
    end

    phone = normalize_phone(phone_raw)
    send_to_contact(row, phone, idx, total, counters)
  rescue StandardError => e
    counters[:failed] += 1
    Rails.logger.error "Campaign Launcher: Failed for #{phone_raw}: #{e.message}"
    row_event(counters, index: idx, total: total, phone: phone_raw, status: 'error', detail: e.message.truncate(200))
  end

  def send_to_contact(row, phone, idx, total, counters)
    name = name_column.present? ? row[name_column].to_s.strip : ''
    contact = find_or_create_contact(phone, name)
    contact_inbox = find_or_create_contact_inbox(contact, phone)
    conversation = find_or_create_conversation(contact, contact_inbox)

    tpl_params = build_template_params(row)
    message_id = send_whatsapp_template(phone, tpl_params)
    create_message_record(conversation, tpl_params, message_id)

    counters[:sent] += 1
    row_event(counters, index: idx, total: total, phone: phone, status: 'sent', detail: "WhatsApp ID: #{message_id || 'queued'}")
  end

  def send_whatsapp_template(phone, tpl_params)
    processor = Whatsapp::TemplateProcessorService.new(channel: channel, template_params: tpl_params)
    tpl_name, namespace, lang_code, processed_parameters = processor.call

    raise 'Template not found or invalid' if tpl_name.blank?

    channel.send_template(phone, {
                            name: tpl_name, namespace: namespace,
                            lang_code: lang_code, parameters: processed_parameters
                          }, nil)
  end

  def create_message_record(conversation, tpl_params, message_id)
    display_content = render_template_content(tpl_params)

    conversation.messages.create!(
      account: account, inbox: inbox, message_type: :outgoing,
      content: display_content, sender: @sender,
      source_id: message_id, additional_attributes: { 'template_params' => tpl_params }
    )
  end

  def render_template_content(tpl_params)
    body_params = tpl_params.dig('processed_params', 'body') || {}
    return "[#{tpl_params['name']}]" if template_body_text.blank?

    text = template_body_text.dup
    body_params.each { |key, value| text.gsub!("{{#{key}}}", value.to_s) }
    text
  end

  def find_or_create_contact(phone, name)
    contact = account.contacts.find_by(phone_number: phone)
    return contact if contact.present?

    account.contacts.create!(phone_number: phone, name: name.presence || phone, contact_type: :lead)
  end

  def find_or_create_contact_inbox(contact, phone)
    ContactInbox.find_or_create_by!(contact: contact, inbox: inbox, source_id: phone.delete('^0-9').last(15))
  end

  def find_or_create_conversation(contact, contact_inbox)
    conversation = Conversation.where(account: account, inbox: inbox, contact: contact).order(created_at: :desc).first
    return conversation if conversation.present?

    Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def build_template_params(row)
    tpl = JSON.parse(template_params_base.to_json)
    body = {}
    (variable_mappings || []).each do |mapping|
      key = mapping[:variable_index] || mapping['variable_index']
      val = row[mapping[:csv_column] || mapping['csv_column']].to_s
      body[key] = val
    end
    tpl['processed_params'] = { 'body' => body }
    tpl
  end

  def normalize_phone(phone_raw)
    digits = phone_raw.gsub(/[^\d+]/, '')
    digits = "+#{digits}" unless digits.start_with?('+')
    digits
  end

  def row_event(counters, **attrs)
    { type: 'row', sent: counters[:sent], failed: counters[:failed], skipped: counters[:skipped] }.merge(attrs)
  end
end
