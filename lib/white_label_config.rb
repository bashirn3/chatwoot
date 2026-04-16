module WhiteLabelConfig
  CONFIG_PATH = Rails.root.join('config/white_label.yml')

  class << self
    def config
      @config ||= load_config
    end

    def brand_name
      config['brand_name'] || 'Chatwoot'
    end

    def logo_url
      config['logo_url'] || '/dashboard/images/logo.svg'
    end

    def favicon_url
      config['favicon_url'] || '/favicon.ico'
    end

    def primary_color
      config['primary_color'] || '#1f93ff'
    end

    def hide_chatwoot_branding?
      config['hide_chatwoot_branding'] == true
    end

    def hide_typebot_branding?
      config['hide_typebot_branding'] == true
    end

    def support_email
      config['support_email']
    end

    def to_frontend_config
      {
        brandName: brand_name,
        logoUrl: logo_url,
        faviconUrl: favicon_url,
        primaryColor: primary_color,
        hideChatwootBranding: hide_chatwoot_branding?,
        hideTypebotBranding: hide_typebot_branding?,
        supportEmail: support_email
      }.compact
    end

    def reload!
      @config = load_config
    end

    private

    def load_config
      return {} unless File.exist?(CONFIG_PATH)

      YAML.load_file(CONFIG_PATH) || {}
    rescue StandardError => e
      Rails.logger.warn "Failed to load white_label.yml: #{e.message}"
      {}
    end
  end
end
