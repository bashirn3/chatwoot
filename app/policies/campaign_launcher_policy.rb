class CampaignLauncherPolicy < ApplicationPolicy
  def upload_csv?
    @account_user.administrator?
  end

  def whatsapp_inboxes?
    @account_user.administrator?
  end

  def validate?
    @account_user.administrator?
  end

  def launch?
    @account_user.administrator?
  end
end
