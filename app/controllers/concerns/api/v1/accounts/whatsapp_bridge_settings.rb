module Api::V1::Accounts::WhatsappBridgeSettings
  extend ActiveSupport::Concern

  def instance_detail
    render json: framework_request(:get, "/api/instances/#{params[:instance_name]}")
  end

  def update_instance
    body = params.permit(:name, :webhookUrl, :customWebhookUrl).to_h.compact
    render json: framework_request(:put, "/api/instances/#{params[:instance_name]}", body)
  end

  def anti_ban
    render json: framework_request(:get, "/api/instances/#{params[:instance_name]}/anti-ban")
  end

  def update_anti_ban
    body = params.permit(:preset, :messagesPerHour, :minDelay, :maxDelay).to_h.compact
    render json: framework_request(:put, "/api/instances/#{params[:instance_name]}/anti-ban", body)
  end

  def behavior
    render json: framework_request(:get, "/api/instances/#{params[:instance_name]}/behavior")
  end

  def update_behavior
    body = params.permit(:typingSimulation, :delayEnabled).to_h.compact
    render json: framework_request(:put, "/api/instances/#{params[:instance_name]}/behavior", body)
  end

  def profile
    render json: framework_request(:get, "/api/instances/#{params[:instance_name]}/profile")
  end

  def update_profile_name
    render json: framework_request(:put, "/api/instances/#{params[:instance_name]}/profile/name", { name: params[:name] })
  end

  def update_profile_picture
    render json: framework_request(:put, "/api/instances/#{params[:instance_name]}/profile/picture", { imageUrl: params[:imageUrl] })
  end

  def update_profile_status
    render json: framework_request(:put, "/api/instances/#{params[:instance_name]}/profile/status", { status: params[:status] })
  end

  def handoff
    render json: framework_request(:get, "/api/instances/#{params[:instance_name]}/handoff")
  end

  def update_handoff
    body = params.permit(:phone, :jid, :active).to_h.compact
    render json: framework_request(:post, "/api/instances/#{params[:instance_name]}/handoff", body)
  end

  def handoff_settings
    render json: framework_request(:get, "/api/instances/#{params[:instance_name]}/handoff/settings")
  end

  def update_handoff_settings
    body = params.permit(resumeKeywords: [], resumeMessage: nil).to_h.compact
    render json: framework_request(:put, "/api/instances/#{params[:instance_name]}/handoff/settings", body)
  end
end
