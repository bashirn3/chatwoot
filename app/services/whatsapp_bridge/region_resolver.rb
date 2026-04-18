module WhatsappBridge
  # Turns a user-selected country ISO code into a concrete region code,
  # performing the UK tie-break live when necessary.
  #
  # Tie-break rules (per the multi-region brief):
  #   - For every country except GB there is exactly one active region.
  #   - For GB, choose whichever of uk-south / uk-west has the most free
  #     proxy pool slots at this moment. Ties fall to uk-south.
  #   - If both UK regions' /api/proxy/pool calls fail, surface an error
  #     so the caller can offer the user a retry instead of silently
  #     picking one.
  class RegionResolver
    POOL_PATH = '/api/proxy/pool'.freeze

    class UnsupportedCountryError < StandardError; end
    class TemporarilyUnavailableError < StandardError; end

    def initialize(country_iso)
      @country_iso = country_iso.to_s.upcase
    end

    def resolve
      candidates = RegionRegistry.for_country(@country_iso)
      raise UnsupportedCountryError, "No region for country #{@country_iso}" if candidates.empty?

      return candidates.first.code if candidates.size == 1

      # Multi-candidate (only GB today). Pick by free pool count.
      choose_by_pool_capacity(candidates)
    end

    private

    def choose_by_pool_capacity(candidates)
      free_counts = candidates.each_with_object({}) do |region, acc|
        acc[region.code] = fetch_free_slots(region.code)
      end

      reachable = free_counts.reject { |_, v| v.nil? }
      raise TemporarilyUnavailableError, "All regions for #{@country_iso} unreachable" if reachable.empty?

      # Sort by: free desc, preference of uk-south on tie, code asc for stability.
      reachable.max_by do |code, free|
        preference = code == 'uk-south' ? 1 : 0
        [free, preference, -code.to_s.length]
      end.first
    end

    def fetch_free_slots(region_code)
      response = RegionalClient.new(region_code).get(POOL_PATH, timeout: 3)
      return nil if response['error'].present?

      pool = response['pool'] || {}
      free = pool['free']
      free.is_a?(Numeric) ? free.to_i : nil
    end
  end
end
