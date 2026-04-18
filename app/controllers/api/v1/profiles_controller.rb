class Api::V1::ProfilesController < Api::BaseController
  before_action :set_user

  def show; end

  def update
    if password_params[:password].present?
      render_could_not_create_error('Invalid current password') and return unless @user.valid_password?(password_params[:current_password])

      @user.update!(password_params.except(:current_password))
    end

    @user.assign_attributes(profile_params)
    @user.custom_attributes.merge!(custom_attributes_params)
    @user.save!
  end

  def avatar
    @user.avatar.attachment.destroy! if @user.avatar.attached?
    @user.reload
  end

  def auto_offline
    @user.account_users.find_by!(account_id: auto_offline_params[:account_id]).update!(auto_offline: auto_offline_params[:auto_offline] || false)
  end

  def availability
    @user.account_users.find_by!(account_id: availability_params[:account_id]).update!(availability: availability_params[:availability])
  end

  def set_active_account
    @user.account_users.find_by(account_id: profile_params[:account_id]).update(active_at: Time.now.utc)
    head :ok
  end

  def resend_confirmation
    @user.send_confirmation_instructions unless @user.confirmed?
    head :ok
  end

  def reset_access_token
    @user.access_token.regenerate_token
    @user.reload
  end

  # DELETE /api/v1/profile
  # Self-service account nuke. For every org the user is the sole admin of,
  # trigger the existing AccountDeletionService (async DeleteObjectJob cascade
  # over inboxes / conversations / contacts / WhatsApp bridge instances).
  # For shared orgs, just drop the AccountUser link. Finally soft-delete the
  # user (email → `<original>-deleted-<ts>.com`) so the original address is
  # free to sign up fresh while we keep an audit trail.
  def destroy
    solo_admin_account_ids = @user.account_users
                                  .where(role: :administrator)
                                  .includes(:account)
                                  .select { |au| au.account.administrators.where.not(id: @user.id).none? }
                                  .map(&:account_id)

    solo_admin_accounts = Account.where(id: solo_admin_account_ids)

    ActiveRecord::Base.transaction do
      solo_admin_accounts.each do |account|
        Current.account = account
        AccountDeletionService.new(account: account).perform
      end

      @user.account_users.destroy_all
      @user.access_token&.destroy

      original_email = @user.email
      suffix = "-deleted-#{Time.current.to_i}.com"
      @user.skip_reconfirmation! if @user.respond_to?(:skip_reconfirmation!)
      @user.update_columns(
        email: "#{original_email}#{suffix}",
        uid: "#{original_email}#{suffix}"
      )
    end

    render json: { success: true, accounts_deleted: solo_admin_accounts.count }
  end

  # POST /api/v1/profile/leave_account { account_id }
  # Removes the user from a specific org without deleting their user record.
  # Refuses to let a sole administrator leave (would orphan the account).
  def leave_account
    account_id = params.require(:account_id)
    au = @user.account_users.find_by(account_id: account_id)
    return render(json: { error: 'Not a member of this account' }, status: :not_found) unless au

    if au.administrator? && au.account.administrators.where.not(id: @user.id).none?
      return render(json: {
        error: 'You are the sole administrator of this organisation. ' \
               'Promote another admin first, or delete the organisation instead.'
      }, status: :unprocessable_entity)
    end

    au.destroy!
    render json: { success: true }
  end

  private

  def set_user
    @user = current_user
  end

  def availability_params
    params.require(:profile).permit(:account_id, :availability)
  end

  def auto_offline_params
    params.require(:profile).permit(:account_id, :auto_offline)
  end

  def profile_params
    params.require(:profile).permit(
      :email,
      :name,
      :display_name,
      :avatar,
      :message_signature,
      :account_id,
      ui_settings: {}
    )
  end

  def custom_attributes_params
    params.require(:profile).permit(:phone_number)
  end

  def password_params
    params.require(:profile).permit(
      :current_password,
      :password,
      :password_confirmation
    )
  end
end
