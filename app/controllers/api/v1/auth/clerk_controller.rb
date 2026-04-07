class Api::V1::Auth::ClerkController < ActionController::API
  def verify
    session_data = clerk_service.verify_session_token(params[:token])
    return render json: { error: 'Invalid session token' }, status: :unauthorized unless session_data

    clerk_user = clerk_service.fetch_user(session_data['user_id'])
    return render json: { error: 'Could not fetch user' }, status: :unprocessable_entity unless clerk_user

    render json: resolve_organization(session_data, clerk_user)
  end

  def select_org
    clerk_user_id = params[:clerk_user_id]
    clerk_org_id = params[:clerk_org_id]

    clerk_user = clerk_service.fetch_user(clerk_user_id)
    return render json: { error: 'Could not fetch user' }, status: :unprocessable_entity unless clerk_user

    org = clerk_service.fetch_organization(clerk_org_id)
    return render json: { error: 'Could not fetch organization' }, status: :unprocessable_entity unless org

    result = sign_in_with_clerk(clerk_user, org)
    render json: result
  end

  private

  def resolve_organization(session_data, clerk_user)
    # If JWT already contains an org_id, use it directly (user selected org in Clerk)
    if session_data['org_id'].present?
      org = clerk_service.fetch_organization(session_data['org_id'])
      return sign_in_with_clerk(clerk_user, org)
    end

    # No org in JWT — check memberships for multi-org picker
    memberships = clerk_service.fetch_user_organization_memberships(session_data['user_id'])
    return sign_in_with_clerk(clerk_user, memberships.first&.dig('organization')) if memberships.length <= 1

    orgs = memberships.map { |m| { id: m.dig('organization', 'id'), name: m.dig('organization', 'name') } }
    { multi_org: true, organizations: orgs, clerk_user_id: session_data['user_id'] }
  end

  def clerk_service
    @clerk_service ||= Clerk::ApiService.new
  end

  def sign_in_with_clerk(clerk_user, clerk_org)
    email = primary_email(clerk_user)
    name = [clerk_user['first_name'], clerk_user['last_name']].compact.join(' ').presence || email.split('@').first

    user = find_or_create_user(clerk_user['id'], email, name, clerk_user['image_url'])
    account = find_or_create_account(clerk_org, user) if clerk_org

    sso_token = user.generate_sso_auth_token
    encoded_email = ERB::Util.url_encode(user.email)

    { email: encoded_email, sso_auth_token: sso_token, account_id: account&.id }
  end

  def find_or_create_user(clerk_user_id, email, name, avatar_url)
    user = User.find_by(clerk_user_id: clerk_user_id)
    user ||= User.from_email(email)

    if user
      user.update!(clerk_user_id: clerk_user_id) if user.clerk_user_id.blank?
    else
      user = User.create!(
        clerk_user_id: clerk_user_id, email: email, name: name,
        password: SecureRandom.alphanumeric(24), confirmed_at: Time.current
      )
      Avatar::AvatarFromUrlJob.perform_later(user, avatar_url) if avatar_url.present?
    end

    user
  end

  def find_or_create_account(clerk_org, user)
    return nil unless clerk_org

    clerk_org_id = clerk_org['id']
    account = Account.find_by(clerk_org_id: clerk_org_id)

    account ||= Account.create!(name: clerk_org['name'] || 'My Organization', clerk_org_id: clerk_org_id)

    AccountUser.find_or_create_by!(account: account, user: user) do |au|
      au.role = :administrator
    end

    account
  end

  def primary_email(clerk_user)
    primary_id = clerk_user['primary_email_address_id']
    email_obj = clerk_user['email_addresses']&.find { |e| e['id'] == primary_id }
    email_obj&.dig('email_address') || clerk_user['email_addresses']&.first&.dig('email_address')
  end
end
