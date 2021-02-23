module MeterReadingsFeeds
  class N3rgyConsent

    # N3RGY_CONSENT_BASE_URL : 'https://consent.data.n3rgy.com/' or 'https://consentsandbox.data.n3rgy.com/'

    def initialize(api_key:, base_url:)
      @api_key = api_key
      @base_url = base_url
    end

    def grant_trusted_consent(mpxn, reference)
      api.grant_trusted_consent(mpxn, reference)
      true
    end

    def withdraw_trusted_consent(mpxn)
      api.withdraw_trusted_consent(mpxn)
      true
    end

    def api
      @api ||= N3rgyConsentApi.new(@api_key, @base_url)
    end
  end
end
