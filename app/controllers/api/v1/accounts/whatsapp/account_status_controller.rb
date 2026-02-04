class Api::V1::Accounts::Whatsapp::AccountStatusController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :set_channel, only: [:show, :sync, :events]

  # GET /api/v1/accounts/:account_id/whatsapp/account_status
  # Returns status for all WhatsApp channels in the account
  def index
    channels = Current.account.inboxes
                      .joins(:channel)
                      .where(channel_type: 'Channel::Whatsapp')
                      .map(&:channel)

    render json: {
      channels: channels.map { |channel| channel_status_json(channel) },
      summary: {
        total: channels.count,
        active: channels.count(&:active?),
        with_issues: channels.count(&:has_issues?),
        low_quality: channels.count { |c| c.quality_rating.in?(%w[YELLOW RED]) }
      }
    }
  end

  # GET /api/v1/accounts/:account_id/whatsapp/account_status/:inbox_id
  # Returns detailed status for a specific WhatsApp channel
  def show
    render json: {
      status: channel_status_json(@channel),
      recent_events: @channel.recent_events(limit: 20).map { |e| event_json(e) }
    }
  end

  # POST /api/v1/accounts/:account_id/whatsapp/account_status/:inbox_id/sync
  # Manually trigger a status sync for a channel
  def sync
    Whatsapp::AccountStatusSyncJob.perform_later(@channel.id)
    render json: { message: 'Status sync initiated' }
  end

  # GET /api/v1/accounts/:account_id/whatsapp/account_status/:inbox_id/events
  # Returns status events history for a channel
  def events
    events = @channel.status_events
                     .order(created_at: :desc)
                     .page(params[:page])
                     .per(params[:per_page] || 25)

    render json: {
      events: events.map { |e| event_json(e) },
      meta: {
        current_page: events.current_page,
        total_pages: events.total_pages,
        total_count: events.total_count
      }
    }
  end

  # GET /api/v1/accounts/:account_id/whatsapp/account_status/alerts
  # Returns channels that need attention
  def alerts
    channels_with_issues = Current.account.inboxes
                                  .joins(:channel)
                                  .where(channel_type: 'Channel::Whatsapp')
                                  .map(&:channel)
                                  .select(&:needs_attention?)

    render json: {
      alerts: channels_with_issues.map do |channel|
        {
          inbox_id: channel.inbox&.id,
          inbox_name: channel.inbox&.name,
          phone_number: channel.phone_number,
          account_status: channel.account_status,
          quality_rating: channel.quality_rating,
          issues: build_issues_list(channel)
        }
      end
    }
  end

  private

  def check_authorization
    authorize :account, :manage_whatsapp_templates?
  end

  def set_channel
    inbox = Current.account.inboxes.find(params[:inbox_id])
    @channel = inbox.channel

    unless @channel.is_a?(Channel::Whatsapp)
      render json: { error: 'Not a WhatsApp inbox' }, status: :bad_request
    end
  end

  def channel_status_json(channel)
    {
      inbox_id: channel.inbox&.id,
      inbox_name: channel.inbox&.name,
      phone_number: channel.phone_number,
      provider: channel.provider,
      account_status: channel.account_status,
      quality_rating: channel.quality_rating,
      messaging_limit_tier: channel.messaging_limit_tier,
      current_throughput: channel.current_throughput,
      business_verification_status: channel.business_verification_status,
      display_name_status: channel.display_name_status,
      account_review_status: channel.account_review_status,
      violations: channel.violation_info,
      restrictions: channel.restrictions,
      last_synced_at: channel.account_status_last_synced_at,
      needs_attention: channel.needs_attention?,
      has_issues: channel.has_issues?
    }
  end

  def event_json(event)
    {
      id: event.id,
      event_type: event.event_type,
      previous_value: event.previous_value,
      new_value: event.new_value,
      event_data: event.event_data,
      source: event.source,
      severity: event.severity,
      message: event.human_readable_message,
      created_at: event.created_at,
      event_timestamp: event.event_timestamp
    }
  end

  def build_issues_list(channel)
    issues = []
    
    if channel.banned?
      issues << { type: 'BANNED', severity: 'critical', message: 'Account has been banned' }
    elsif channel.restricted?
      issues << { type: 'RESTRICTED', severity: 'high', message: 'Account has restrictions' }
    elsif channel.flagged?
      issues << { type: 'FLAGGED', severity: 'medium', message: 'Account is under review' }
    end

    if channel.quality_rating == 'RED'
      issues << { type: 'LOW_QUALITY', severity: 'high', message: 'Quality rating is RED' }
    elsif channel.quality_rating == 'YELLOW'
      issues << { type: 'MEDIUM_QUALITY', severity: 'medium', message: 'Quality rating is YELLOW' }
    end

    if channel.violation_info.present? && channel.violation_info.any?
      issues << { type: 'VIOLATIONS', severity: 'high', message: "#{channel.violation_info.count} policy violations" }
    end

    if channel.restrictions.present? && channel.restrictions.any?
      issues << { type: 'RESTRICTIONS', severity: 'medium', message: "#{channel.restrictions.count} active restrictions" }
    end

    issues
  end
end
