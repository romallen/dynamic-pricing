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

      rate = call_api(cache_key)
      return unless rate

      if rate.success?
        handle_success(rate, cache_key)
      else
        handle_error(rate, cache_key)
      end
    end

    private

    def serve_from_cache?(cache_key)
      cached_rate = Rails.cache.read(cache_key)
      return false unless cached_rate

      Rails.logger.info "[PricingService] Cache hit for key=#{cache_key}"
      @result = cached_rate
      true
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
      parsed_rate = JSON.parse(rate.body)
      @result = extract_rate(parsed_rate)

      if @result.nil?
        errors << "No rate found for the given parameters"
        Rails.logger.error "[PricingService] No matching rate in response (key=#{cache_key})"
        return
      end

      store_in_cache(cache_key)
    rescue JSON::ParserError
      errors << "Pricing model returned an unexpected response"
      Rails.logger.error "[PricingService] JSON parse error (key=#{cache_key})"
    end

    def extract_rate(parsed_rate)
      parsed_rate["rates"].detect do |r|
        r["period"] == @period && r["hotel"] == @hotel && r["room"] == @room
      end&.dig("rate")
    end

    def store_in_cache(cache_key)
      Rails.cache.write(cache_key, @result, expires_in: CACHE_TTL)
      Rails.logger.info "[PricingService] Cached rate for key=#{cache_key}, expires_in=#{CACHE_TTL}"
    end

    def handle_error(rate, cache_key)
      message = begin
        JSON.parse(rate.body)["error"] || "Pricing model returned an error"
      rescue JSON::ParserError
        "Pricing model returned an error"
      end
      errors << message
      Rails.logger.error "[PricingService] API error: #{message} (key=#{cache_key})"
    end
  end
end
