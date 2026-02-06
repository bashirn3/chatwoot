# frozen_string_literal: true

class Api::V1::Accounts::Whatsapp::TemplatesController < Api::V1::Accounts::BaseController
  before_action :set_template, only: [:show, :update, :destroy, :submit, :submit_to_channels, :sync, :reset_to_draft, :duplicate]
  before_action :check_authorization

  def index
    @templates = fetch_templates
                 .order(created_at: :desc)
                 .page(params[:page])
                 .per(params[:per_page] || 25)

    render json: {
      payload: @templates.map { |t| template_response(t) },
      meta: {
        count: @templates.total_count,
        current_page: @templates.current_page,
        total_pages: @templates.total_pages,
        total_count: @templates.total_count
      }
    }
  end

  def show
    render json: template_response(@template)
  end

  def create
    @template = WhatsappTemplate.new(template_params)
    @template.account = Current.account
    @template.user = Current.user
    @template.clerk_organization_id = current_organization_id

    if @template.save
      render json: template_response(@template), status: :created
    else
      render json: { errors: @template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    unless @template.editable?
      return render json: { error: 'Template cannot be edited in current status' }, status: :unprocessable_entity
    end

    if @template.update(template_params)
      render json: template_response(@template)
    else
      render json: { errors: @template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    service = Whatsapp::TemplateManagementService.new(template: @template)
    result = service.delete_template

    if result[:success]
      render json: { message: result[:message] }, status: :ok
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/accounts/:account_id/whatsapp/templates/:id/submit
  def submit
    service = Whatsapp::TemplateManagementService.new(template: @template)
    result = service.submit_template

    if result[:success]
      render json: template_response(@template.reload), status: :ok
    else
      render json: { error: result[:error], details: result[:details] }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/accounts/:account_id/whatsapp/templates/:id/submit_to_channels
  # Submit template to multiple WhatsApp channels
  def submit_to_channels
    channel_ids = params[:channel_ids] || []
    
    if channel_ids.empty?
      return render json: { error: 'No channels specified' }, status: :unprocessable_entity
    end

    channels = Channel::Whatsapp.where(id: channel_ids, account_id: Current.account.id)
    
    if channels.empty?
      return render json: { error: 'No valid channels found' }, status: :not_found
    end

    results = []
    channels.each do |channel|
      # Clone template for each channel if not the primary one
      if @template.channel_whatsapp_id == channel.id
        template_to_submit = @template
      else
        # Create a copy for this channel
        template_to_submit = @template.dup
        template_to_submit.channel_whatsapp_id = channel.id
        template_to_submit.meta_template_id = nil
        template_to_submit.status = 'DRAFT'
        template_to_submit.submitted_at = nil
        template_to_submit.save!
      end

      service = Whatsapp::TemplateManagementService.new(template: template_to_submit)
      result = service.submit_template
      
      results << {
        channel_id: channel.id,
        channel_name: channel.inbox&.name || channel.phone_number,
        success: result[:success],
        error: result[:error],
        template_id: template_to_submit.id
      }
    end

    successful = results.count { |r| r[:success] }
    failed = results.count { |r| !r[:success] }

    render json: {
      message: "Submitted to #{successful} channel(s), #{failed} failed",
      results: results
    }, status: :ok
  end

  # GET /api/v1/accounts/:account_id/whatsapp/templates/channels
  # List all WhatsApp channels for template submission
  def channels
    whatsapp_channels = Channel::Whatsapp.joins(:inbox)
                                         .where(inboxes: { account_id: Current.account.id })
                                         .select('channel_whatsapp.id, channel_whatsapp.phone_number, inboxes.name as inbox_name')

    render json: whatsapp_channels.map { |c|
      {
        id: c.id,
        phone_number: c.phone_number,
        name: c.inbox_name
      }
    }
  end

  # POST /api/v1/accounts/:account_id/whatsapp/templates/:id/sync
  def sync
    service = Whatsapp::TemplateManagementService.new(template: @template)
    result = service.sync_status

    if result[:success]
      render json: template_response(@template.reload), status: :ok
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/accounts/:account_id/whatsapp/templates/:id/reset_to_draft
  def reset_to_draft
    unless @template.resettable_to_draft?
      return render json: { error: 'Template cannot be reset to draft in current status' }, status: :unprocessable_entity
    end

    if @template.reset_to_draft!
      render json: template_response(@template.reload), status: :ok
    else
      render json: { error: 'Failed to reset template to draft' }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/accounts/:account_id/whatsapp/templates/:id/duplicate
  # Creates a draft copy of an existing template (useful for editing approved templates)
  def duplicate
    new_name = params[:new_name] || "#{@template.name}_copy"
    
    begin
      copy = @template.create_draft_copy(new_name: new_name)
      render json: template_response(copy), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/accounts/:account_id/whatsapp/templates/sync_all
  # Syncs templates from Meta for all WhatsApp channels or a specific channel
  def sync_all
    channels = if params[:channel_id].present?
                 [Channel::Whatsapp.find_by(id: params[:channel_id], account_id: Current.account.id)].compact
               else
                 fetch_all_whatsapp_channels
               end

    if channels.empty?
      return render json: { error: 'No WhatsApp channels found' }, status: :not_found
    end

    total_synced = 0
    results = []

    channels.each do |channel|
      result = Whatsapp::TemplateManagementService.sync_all_templates(channel)
      results << {
        channel_id: channel.id,
        channel_name: channel.inbox&.name || channel.phone_number,
        success: result[:success],
        count: result[:count] || 0,
        error: result[:error]
      }
      total_synced += result[:count] || 0 if result[:success]
    end

    render json: {
      message: "Synced #{total_synced} templates from #{channels.count} channel(s)",
      total_synced: total_synced,
      results: results
    }, status: :ok
  end

  private

  def fetch_all_whatsapp_channels
    channel_ids = Current.account.inboxes
                         .where(channel_type: 'Channel::Whatsapp')
                         .pluck(:channel_id)
    Channel::Whatsapp.where(id: channel_ids)
  end

  # GET /api/v1/accounts/:account_id/whatsapp/templates/languages
  def languages
    render json: WhatsappTemplate::SUPPORTED_LANGUAGES
  end

  # GET /api/v1/accounts/:account_id/whatsapp/templates/sample
  def sample
    samples = {
      appointment_reminder: {
        name: 'appointment_reminder',
        language: 'en',
        category: 'UTILITY',
        header_type: 'TEXT',
        header_content: 'Appointment Reminder',
        body_text: 'Hi {{1}}, this is a reminder for your appointment on {{2}} at {{3}}. Please reply CONFIRM to confirm or RESCHEDULE to change your appointment.',
        footer_text: 'Reply STOP to opt out',
        buttons: [
          { type: 'QUICK_REPLY', text: 'Confirm' },
          { type: 'QUICK_REPLY', text: 'Reschedule' }
        ]
      },
      order_confirmation: {
        name: 'order_confirmation',
        language: 'en',
        category: 'UTILITY',
        header_type: 'TEXT',
        header_content: 'Order Confirmed!',
        body_text: "Thank you {{1}}! Your order \#{{2}} has been confirmed.\n\nTotal: ${{3}}\nEstimated delivery: {{4}}\n\nTrack your order using the button below.",
        footer_text: 'Thank you for your purchase',
        buttons: [
          { type: 'URL', text: 'Track Order', url: 'https://example.com/track/{{1}}', url_example: 'https://example.com/track/12345' }
        ]
      },
      promotional_offer: {
        name: 'promotional_offer',
        language: 'en',
        category: 'MARKETING',
        header_type: 'IMAGE',
        header_content: '',
        body_text: "Exclusive offer for you, {{1}}!\n\nGet {{2}}% OFF on your next purchase. Use code: {{3}}\n\nValid until {{4}}. Do not miss out!",
        footer_text: 'Terms and conditions apply',
        buttons: [
          { type: 'URL', text: 'Shop Now', url: 'https://example.com/shop' },
          { type: 'COPY_CODE', example: 'SAVE20' }
        ]
      },
      authentication_otp: {
        name: 'authentication_otp',
        language: 'en',
        category: 'AUTHENTICATION',
        body_text: 'Your verification code is {{1}}. This code expires in 10 minutes. Do not share this code with anyone.',
        buttons: [
          { type: 'COPY_CODE', example: '123456' }
        ]
      }
    }

    render json: samples
  end

  private

  def set_template
    @template = WhatsappTemplate.find_by!(id: params[:id], account_id: Current.account.id)
  end

  def fetch_templates
    templates = WhatsappTemplate.where(account_id: Current.account.id)

    # Filter by organization if Clerk organization ID is present
    if current_organization_id.present?
      templates = templates.where(clerk_organization_id: current_organization_id)
                          .or(templates.where(clerk_organization_id: nil, user_id: Current.user.id))
    end

    # Apply filters
    templates = templates.where(status: params[:status].upcase) if params[:status].present?
    templates = templates.where(category: params[:category].upcase) if params[:category].present?
    templates = templates.where(channel_whatsapp_id: params[:channel_id]) if params[:channel_id].present?
    templates = templates.where('name ILIKE ?', "%#{params[:search]}%") if params[:search].present?

    templates
  end

  def current_organization_id
    # Support for Clerk integration - extract org ID from JWT or header
    # This will be set by the Clerk middleware when integrated
    request.headers['X-Clerk-Organization-Id'] || params[:organization_id]
  end

  def template_params
    params.require(:template).permit(
      :name,
      :language,
      :category,
      :channel_whatsapp_id,
      :header_type,
      :header_content,
      :body_text,
      :footer_text,
      :location_latitude,
      :location_longitude,
      :location_name,
      :location_address,
      buttons: [:type, :text, :url, :url_example, :phone_number, :example],
      body_params: [:index, :example],
      header_params: [:index, :example]
    )
  end

  def template_response(template)
    {
      id: template.id,
      name: template.name,
      language: template.language,
      language_name: WhatsappTemplate::SUPPORTED_LANGUAGES[template.language],
      category: template.category,
      status: template.status,
      quality_score: template.quality_score,
      rejection_reason: template.rejection_reason,
      header_type: template.header_type,
      header_content: template.header_content,
      header_params: template.header_params,
      body_text: template.body_text,
      body_params: template.body_params,
      body_variable_count: template.body_variable_count,
      footer_text: template.footer_text,
      buttons: template.buttons,
      location: template.header_location? ? {
        latitude: template.location_latitude,
        longitude: template.location_longitude,
        name: template.location_name,
        address: template.location_address
      } : nil,
      meta_template_id: template.meta_template_id,
      channel_whatsapp_id: template.channel_whatsapp_id,
      channel_name: template.channel_whatsapp&.inbox&.name,
      channel_phone: template.channel_whatsapp&.phone_number,
      clerk_organization_id: template.clerk_organization_id,
      user_id: template.user_id,
      submitted_at: template.submitted_at,
      approved_at: template.approved_at,
      rejected_at: template.rejected_at,
      last_synced_at: template.last_synced_at,
      editable: template.editable?,
      submittable: template.submittable?,
      created_at: template.created_at,
      updated_at: template.updated_at
    }
  end

  # POST /api/v1/accounts/:account_id/whatsapp/templates/import_from_meta
  # Imports all templates from Meta for all channels
  # This should be called when the templates page loads
  def import_from_meta
    channels = fetch_all_whatsapp_channels
    
    if channels.empty?
      return render json: { 
        success: false, 
        message: 'No WhatsApp channels configured. Please add a WhatsApp channel first.' 
      }, status: :ok
    end

    total_imported = 0
    results = []

    channels.each do |channel|
      result = Whatsapp::TemplateManagementService.sync_all_templates(channel)
      channel_info = {
        channel_id: channel.id,
        channel_name: channel.inbox&.name || channel.phone_number,
        success: result[:success],
        count: result[:count] || 0,
        error: result[:error]
      }
      results << channel_info
      total_imported += result[:count] || 0 if result[:success]
    end

    render json: {
      success: true,
      message: "Imported #{total_imported} templates from #{channels.count} channel(s)",
      total_imported: total_imported,
      results: results
    }, status: :ok
  end

  def find_whatsapp_channel
    if params[:channel_id].present?
      Channel::Whatsapp.find_by(id: params[:channel_id], account_id: Current.account.id)
    else
      Current.account.inboxes.find_by(channel_type: 'Channel::Whatsapp')&.channel
    end
  end

  def check_authorization
    authorize(Current.account, :manage_whatsapp_templates?)
  rescue Pundit::NotAuthorizedError
    render json: { error: 'You are not authorized to manage WhatsApp templates' }, status: :forbidden
  end
end
