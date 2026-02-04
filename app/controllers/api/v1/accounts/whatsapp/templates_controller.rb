# frozen_string_literal: true

class Api::V1::Accounts::Whatsapp::TemplatesController < Api::V1::Accounts::BaseController
  before_action :set_template, only: [:show, :update, :destroy, :submit, :sync]
  before_action :check_authorization

  def index
    @templates = fetch_templates
                 .order(created_at: :desc)
                 .page(params[:page])
                 .per(params[:per_page] || 25)
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

  # POST /api/v1/accounts/:account_id/whatsapp/templates/sync_all
  def sync_all
    channel = find_whatsapp_channel

    unless channel
      return render json: { error: 'No WhatsApp channel found' }, status: :not_found
    end

    result = Whatsapp::TemplateManagementService.sync_all_templates(channel)

    if result[:success]
      render json: { message: "Synced #{result[:count]} templates from Meta" }, status: :ok
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
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
