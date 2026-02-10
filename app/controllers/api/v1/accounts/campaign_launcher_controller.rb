require 'csv'

class Api::V1::Accounts::CampaignLauncherController < Api::V1::Accounts::BaseController
  include ActionController::Live

  before_action :check_authorization

  def upload_csv
    file = params[:file]
    return render json: { error: 'No file provided' }, status: :unprocessable_entity if file.blank?

    csv_data = parse_csv(file)
    return render json: { error: 'CSV is empty' }, status: :unprocessable_entity if csv_data[:rows].empty?

    cache_key = csv_cache_key
    Redis::Alfred.set(cache_key, csv_data[:rows].to_json, ex: 3600)

    render json: { headers: csv_data[:headers], row_count: csv_data[:rows].length, preview: csv_data[:rows].first(5) }
  end

  def whatsapp_inboxes
    inboxes = Current.account.inboxes.where(channel_type: 'Channel::Whatsapp').map do |inbox|
      channel = inbox.channel
      templates = (channel.message_templates || []).select { |t| t['status']&.downcase == 'approved' }
      { id: inbox.id, name: inbox.name, templates: templates.map { |t| format_template(t) } }
    end

    render json: { inboxes: inboxes }
  end

  def validate
    csv_rows = load_csv_from_cache
    errors = run_validations(csv_rows)
    render json: { valid: errors.empty?, errors: errors, total_recipients: csv_rows&.length || 0 }
  end

  def launch
    csv_rows = load_csv_from_cache
    return render json: { error: 'No CSV data found' }, status: :unprocessable_entity if csv_rows.blank?

    inbox = Current.account.inboxes.find_by(id: params[:inbox_id])
    return render json: { error: 'Inbox not found' }, status: :not_found if inbox.blank?

    setup_sse_headers
    service = build_campaign_service(csv_rows, inbox)
    service.each_row { |event| write_sse(event) }
  ensure
    response.stream.close
  end

  private

  def check_authorization
    authorize :campaign_launcher
  end

  def csv_cache_key
    "campaign_launcher:#{Current.account.id}:#{current_user.id}"
  end

  def parse_csv(file)
    content = file.read.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    content = content.delete_prefix("\xEF\xBB\xBF")

    rows = []
    headers = nil
    CSV.parse(content, headers: true) do |row|
      headers ||= row.headers
      rows << row.to_h
    end

    { headers: headers || [], rows: rows }
  end

  def load_csv_from_cache
    data = Redis::Alfred.get(csv_cache_key)
    return nil if data.blank?

    JSON.parse(data)
  end

  def run_validations(csv_rows)
    errors = []
    errors << 'No CSV uploaded — please upload a CSV first' if csv_rows.blank?
    return errors if csv_rows.blank?

    headers = csv_rows.first&.keys || []
    errors << "Phone column '#{params[:phone_column]}' not found in CSV" unless headers.include?(params[:phone_column])
    validate_variable_mappings(headers, errors)
    validate_sample_phone(csv_rows, errors)
    errors
  end

  def validate_variable_mappings(headers, errors)
    (params[:variable_mappings] || []).each do |mapping|
      col = mapping[:csv_column] || mapping['csv_column']
      errors << "Mapped column '#{col}' not found in CSV" unless headers.include?(col)
    end
  end

  def validate_sample_phone(csv_rows, errors)
    sample = csv_rows.first&.dig(params[:phone_column]).to_s.strip
    digits = sample.gsub(/[^\d]/, '')
    errors << "Sample phone '#{sample}' looks invalid" if digits.length < 7 || digits.length > 15
  end

  def setup_sse_headers
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'
  end

  def build_campaign_service(csv_rows, inbox)
    Whatsapp::CsvCampaignService.new(
      account: Current.account, inbox: inbox, csv_rows: csv_rows, sender: current_user,
      template_params_base: {
        'name' => params[:template_name], 'namespace' => params[:template_namespace].presence || '',
        'language' => params[:template_language], 'processed_params' => { 'body' => {} }
      },
      phone_column: params[:phone_column], name_column: params[:name_column],
      variable_mappings: params[:variable_mappings], delay_ms: params[:delay_ms],
      template_body_text: params[:template_body_text]
    )
  end

  def format_template(template)
    body_text, body_vars = extract_body_info(template)
    {
      name: template['name'], language: template['language'], category: template['category'],
      status: template['status'], body_text: body_text, body_variables: body_vars,
      components: template['components'] || [], parameter_format: template['parameter_format']
    }
  end

  def extract_body_info(template)
    body_comp = (template['components'] || []).find { |c| c['type'] == 'BODY' }
    return ['', []] if body_comp.blank?

    text = body_comp['text'] || ''
    [text, text.scan(/\{\{(\w+)\}\}/).flatten.uniq]
  end

  def write_sse(data)
    response.stream.write("data: #{data.to_json}\n\n")
  end
end
