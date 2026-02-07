class Api::V1::Accounts::Whatsapp::AccountStatusController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :set_channel, only: [:show, :sync, :events]

  # GET /api/v1/accounts/:account_id/whatsapp/account_status
  # Returns status for all WhatsApp channels in the account
  def index
    channels = fetch_whatsapp_channels

    render json: {
      channels: channels.map { |channel| channel_status_json(channel) },
      summary: {
        total: channels.count,
        active: channels.count { |c| c.active? },
        with_issues: channels.count { |c| c.has_issues? },
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
    channels_with_issues = fetch_whatsapp_channels.select { |c| c.needs_attention? }

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
    authorize Current.account, :manage_whatsapp_templates?
  end

  def fetch_whatsapp_channels
    # Get WhatsApp channel IDs from inboxes
    channel_ids = Current.account.inboxes
                         .where(channel_type: 'Channel::Whatsapp')
                         .pluck(:channel_id)
    
    # Fetch the actual channels
    Channel::Whatsapp.where(id: channel_ids)
  end

  def set_channel
    inbox = Current.account.inboxes.find(params[:inbox_id])
    @channel = inbox.channel

    unless @channel.is_a?(Channel::Whatsapp)
      render json: { error: 'Not a WhatsApp inbox' }, status: :bad_request
    end
  end

  def channel_status_json(channel)
    inbox = channel.inbox
    messages_stats = calculate_message_stats(inbox)

    {
      inbox_id: inbox&.id,
      inbox_name: inbox&.name,
      phone_number: channel.phone_number,
      provider: channel.provider,
      account_status: channel.account_status,
      quality_rating: channel.quality_rating,
      messaging_limit_tier: channel.messaging_limit_tier,
      messaging_limit_number: messaging_limit_number(channel.messaging_limit_tier),
      current_throughput: channel.current_throughput,
      business_verification_status: channel.business_verification_status,
      display_name_status: channel.display_name_status,
      account_review_status: channel.account_review_status,
      violations: channel.violation_info,
      restrictions: channel.restrictions,
      last_synced_at: channel.account_status_last_synced_at,
      needs_attention: channel.needs_attention?,
      has_issues: channel.has_issues?,
      messages_sent_today: messages_stats[:today],
      messages_sent_24h: messages_stats[:last_24h],
      messages_sent_total: messages_stats[:total]
    }
  end

  def calculate_message_stats(inbox)
    return { today: 0, last_24h: 0, total: 0 } unless inbox

    # Count outgoing messages (message_type = 1 means outgoing)
    messages = Message.joins(:conversation)
                      .where(conversations: { inbox_id: inbox.id })
                      .where(message_type: 1)

    {
      today: messages.where('messages.created_at >= ?', Time.current.beginning_of_day).count,
      last_24h: messages.where('messages.created_at >= ?', 24.hours.ago).count,
      total: messages.count
    }
  end

  def messaging_limit_number(tier)
    return nil unless tier

    limits = {
      'TIER_50' => 50,
      'TIER_250' => 250,
      'TIER_1K' => 1000,
      'TIER_10K' => 10_000,
      'TIER_100K' => 100_000,
      'UNLIMITED' => nil
    }
    limits[tier]
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
