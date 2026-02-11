class Webhooks::ClerkController < ActionController::API
  before_action :verify_webhook_signature

  def process_payload
    event_type = params[:type]

    case event_type
    when 'organization.created'
      handle_organization_created(params[:data])
    when 'organizationMembership.created'
      handle_membership_created(params[:data])
    when 'organizationMembership.deleted'
      handle_membership_deleted(params[:data])
    end

    head :ok
  end

  private

  def handle_organization_created(data)
    clerk_org_id = data[:id]
    return if Account.exists?(clerk_org_id: clerk_org_id)

    Account.create!(name: data[:name] || 'New Organization', clerk_org_id: clerk_org_id)
  end

  def handle_membership_created(data)
    clerk_org_id = data.dig(:organization, :id)
    clerk_user_id = data.dig(:public_user_data, :user_id)
    role = data[:role]

    account = Account.find_by(clerk_org_id: clerk_org_id)
    user = User.find_by(clerk_user_id: clerk_user_id)

    return unless account && user
    return if AccountUser.exists?(account: account, user: user)

    chatwoot_role = role == 'admin' ? :administrator : :agent
    AccountUser.create!(account: account, user: user, role: chatwoot_role)
  end

  def handle_membership_deleted(data)
    clerk_org_id = data.dig(:organization, :id)
    clerk_user_id = data.dig(:public_user_data, :user_id)

    account = Account.find_by(clerk_org_id: clerk_org_id)
    user = User.find_by(clerk_user_id: clerk_user_id)

    return unless account && user

    AccountUser.find_by(account: account, user: user)&.destroy
  end

  def verify_webhook_signature
    webhook_secret = ENV.fetch('CLERK_WEBHOOK_SECRET', nil)
    return head :unauthorized unless webhook_secret
    return head :unauthorized unless valid_svix_headers?

    expected = compute_expected_signature(webhook_secret)
    signatures = request.headers['svix-signature'].split
    return if signatures.any? { |sig| ActiveSupport::SecurityUtils.secure_compare(sig, expected) }

    head :unauthorized
  end

  def valid_svix_headers?
    %w[svix-id svix-timestamp svix-signature].all? { |h| request.headers[h].present? }
  end

  def compute_expected_signature(webhook_secret)
    secret = webhook_secret.delete_prefix('whsec_')
    decoded_secret = Base64.decode64(secret)
    payload = "#{request.headers['svix-id']}.#{request.headers['svix-timestamp']}.#{request.raw_post}"
    "v1,#{Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', decoded_secret, payload))}"
  end
end
