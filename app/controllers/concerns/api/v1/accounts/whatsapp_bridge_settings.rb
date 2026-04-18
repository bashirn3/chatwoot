module Api::V1::Accounts::WhatsappBridgeSettings
  extend ActiveSupport::Concern

  def instance_detail
    render json: bridge_client.get("/api/instances/#{params[:instance_name]}")
  end

  def update_instance
    body = params.permit(:name, :webhookUrl, :customWebhookUrl).to_h.compact
    render json: bridge_client.put("/api/instances/#{params[:instance_name]}", body)
  end

  def anti_ban
    render json: bridge_client.get("/api/instances/#{params[:instance_name]}/anti-ban")
  end

  def update_anti_ban
    body = params.permit(:preset, :messagesPerHour, :minDelay, :maxDelay).to_h.compact
    render json: bridge_client.put("/api/instances/#{params[:instance_name]}/anti-ban", body)
  end

  def behavior
    render json: bridge_client.get("/api/instances/#{params[:instance_name]}/behavior")
  end

  def update_behavior
    body = params.permit(:typingSimulation, :delayEnabled).to_h.compact
    render json: bridge_client.put("/api/instances/#{params[:instance_name]}/behavior", body)
  end

  def profile
    render json: bridge_client.get("/api/instances/#{params[:instance_name]}/profile")
  end

  def update_profile_name
    render json: bridge_client.put("/api/instances/#{params[:instance_name]}/profile/name", { name: params[:name] })
  end

  def update_profile_picture
    render json: bridge_client.put("/api/instances/#{params[:instance_name]}/profile/picture", { imageUrl: params[:imageUrl] })
  end

  def update_profile_status
    render json: bridge_client.put("/api/instances/#{params[:instance_name]}/profile/status", { status: params[:status] })
  end

  def handoff
    render json: bridge_client.get("/api/instances/#{params[:instance_name]}/handoff")
  end

  def update_handoff
    body = params.permit(:phone, :jid, :active).to_h.compact
    render json: bridge_client.post("/api/instances/#{params[:instance_name]}/handoff", body)
  end

  def handoff_settings
    render json: bridge_client.get("/api/instances/#{params[:instance_name]}/handoff/settings")
  end

  def update_handoff_settings
    body = params.permit(resumeKeywords: [], resumeMessage: nil).to_h.compact
    render json: bridge_client.put("/api/instances/#{params[:instance_name]}/handoff/settings", body)
  end

  private

  # All settings endpoints operate on an existing instance; routing is based
  # on the channel's persisted region, not an ENV default.
  def bridge_client
    regional_client_for_instance(params[:instance_name])
  end
end
