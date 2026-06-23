module Api::V1
  class PricingService < BaseService
    CACHE_TTL = 5.minutes

    def initialize(period:, hotel:, room:)
      super()
      @period = period
      @hotel = hotel
      @room = room
    end

    def run
      cache_key = "pricing/#{@period}/#{@hotel}/#{@room}"
      return if serve_from_cache?(cache_key)

      # NOTE: On a cache miss, concurrent requests for the same key will each
      # call the API (a "cache stampede"). With only 36 param combinations and
      # a 5-minute TTL this stays well within the 1,000 calls/day budget, so we
      # intentionally avoid the complexity of a single-flight lock here.
      rate = call_api(cache_key)
      return unless rate

      if rate.success?
        handle_success(rate, cache_key)
      else
        handle_error(rate, cache_key)
      end
    end

    private

    # The cache is a best-effort optimization: if reading it fails for any
    # reason, log it and fall through to a normal API fetch.
    def serve_from_cache?(cache_key)
      cached_rate = Rails.cache.read(cache_key)
      return false unless cached_rate

      Rails.logger.info "[PricingService] Cache hit for key=#{cache_key}"
      @result = cached_rate
      true
    rescue StandardError => e
      Rails.logger.error "[PricingService] Cache read failed for key=#{cache_key}: #{e.message}"
      false
    end

    def call_api(cache_key)
      Rails.logger.info "[PricingService] Cache miss for key=#{cache_key}, fetching from API"
      RateApiClient.get_rate(period: @period, hotel: @hotel, room: @room)
    rescue StandardError => e
      errors << "Could not reach the pricing model: #{e.message}"
      Rails.logger.error "[PricingService] Network error: #{e.message} (key=#{cache_key})"
      nil
    end

    def handle_success(rate, cache_key)
      parsed_rate = parse_json_object(rate.body)
      if parsed_rate.nil?
        errors << "Pricing model returned an unexpected response"
        Rails.logger.error "[PricingService] Unparseable success response (key=#{cache_key})"
        return
      end

      @result = extract_rate(parsed_rate)
      if @result.nil?
        errors << "No rate found for the given parameters"
        Rails.logger.error "[PricingService] No matching rate in response (key=#{cache_key})"
        return
      end

      store_in_cache(cache_key)
    end

    def handle_error(rate, cache_key)
      parsed = parse_json_object(rate.body)
      message = parsed&.dig("error") || "Pricing model returned an error"
      errors << message
      Rails.logger.error "[PricingService] API error: #{message} (key=#{cache_key})"
    end

    # Finds the rate matching our parameters. Guards every step so a response
    # that is valid JSON but the wrong shape returns nil instead of raising.
    def extract_rate(parsed_rate)
      rates = parsed_rate["rates"]
      return nil unless rates.is_a?(Array)

      rates.detect do |r|
        r.is_a?(Hash) && r["period"] == @period && r["hotel"] == @hotel && r["room"] == @room
      end&.dig("rate")
    end

    # A cache write failure must not fail the request — we already have the rate.
    def store_in_cache(cache_key)
      Rails.cache.write(cache_key, @result, expires_in: CACHE_TTL)
      Rails.logger.info "[PricingService] Cached rate for key=#{cache_key}, expires_in=#{CACHE_TTL}"
    rescue StandardError => e
      Rails.logger.error "[PricingService] Cache write failed for key=#{cache_key}: #{e.message}"
    end

    # Parses a JSON body and returns it only if it is a JSON object (Hash).
    # Returns nil for invalid JSON or any non-object (array, number, null) so
    # callers never crash while indexing an unexpected shape.
    def parse_json_object(body)
      parsed = JSON.parse(body)
      parsed.is_a?(Hash) ? parsed : nil
    rescue JSON::ParserError
      nil
    end
  end
end
