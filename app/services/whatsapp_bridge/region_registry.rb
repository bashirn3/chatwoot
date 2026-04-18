require 'yaml'
require 'erb'

module WhatsappBridge
  # Reads config/whatsapp_regions.yml (with ERB env interpolation), caches
  # the parsed map, and exposes read-only lookups. URLs / API keys come from
  # ENV via ERB — if a region's env vars are blank the region is still in
  # the registry but `#configured?` returns false and `#active?` is forced
  # to false (i.e. it's never surfaced in the UI).
  class RegionRegistry
    CONFIG_PATH = Rails.root.join('config/whatsapp_regions.yml').to_s

    class << self
      def for(code)
        all[code.to_s.downcase]
      end

      # Regions shown on the country picker (active + fully configured).
      def active
        all.select { |_, r| r.active? }
      end

      # All regions that have URL + API key set (active or legacy).
      def configured
        all.select { |_, r| r.configured? }
      end

      def legacy
        all['legacy']
      end

      # Regions that cover a given ISO-3166-1 alpha-2 country.
      # Normally one, but GB → [uk-south, uk-west].
      def for_country(iso)
        iso = iso.to_s.upcase
        active.values.select { |r| r.country == iso }
      end

      def reset!
        @all = nil
      end

      private

      def all
        @all ||= load_config
      end

      def load_config
        raw = File.read(CONFIG_PATH)
        parsed = YAML.safe_load(ERB.new(raw).result, aliases: true, permitted_classes: [Symbol]) || {}
        parsed.each_with_object({}) do |(code, attrs), acc|
          acc[code.to_s.downcase] = Region.new(code.to_s.downcase, (attrs || {}).symbolize_keys)
        end
      rescue StandardError => e
        Rails.logger.error("[WhatsappBridge] RegionRegistry failed to load: #{e.class} #{e.message}")
        {}
      end
    end

    # Value object for a single region entry. Never leaks the API key
    # outside of .api_key — #to_public_h is safe to serialise to the UI.
    class Region
      attr_reader :code, :url, :api_key, :country, :label, :lat, :lng, :active_flag, :legacy

      def initialize(code, attrs)
        @code = code
        @url = attrs[:url].to_s
        @api_key = attrs[:api_key].to_s
        # YAML 1.1 parses bare `no`/`NO`/`yes`/`on`/`off` as booleans. The
        # config should quote these, but we harden here so a stray value
        # still surfaces as the intended ISO code at runtime.
        country_raw = attrs[:country]
        @country = case country_raw
                   when true then 'YES'
                   when false then 'NO'
                   else country_raw.to_s.upcase
                   end
        @label = attrs[:label].to_s
        @lat = attrs[:lat]
        @lng = attrs[:lng]
        @active_flag = attrs.key?(:active) ? attrs[:active] : false
        @legacy = attrs[:legacy] == true
      end

      def configured?
        url.present? && api_key.present?
      end

      # A region is only offered to users if it's flagged active AND has
      # the env vars present. Roll out by adding env vars, no code changes.
      def active?
        active_flag && configured?
      end

      def legacy?
        @legacy
      end

      # Safe hash for the UI — never includes api_key.
      def to_public_h
        {
          code: code,
          country: country,
          label: label,
          lat: lat,
          lng: lng,
          active: active?,
          legacy: legacy?
        }
      end
    end
  end
end
