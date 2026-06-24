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
      hit = true

      @result = Rails.cache.fetch(cache_key, expires_in: CACHE_TTL, race_condition_ttl: 5, skip_nil: true) do
        hit = false
        log_event(:info, "cache_miss", key: cache_key)
        resolve_from_api(cache_key)
      end

      log_event(:info, "cache_hit", key: cache_key) if @result && hit
    rescue StandardError => e
      log_event(:error, "cache_read_failed", key: cache_key, error: e.message)
    end

    private

    def resolve_from_api(cache_key)
      rate = call_api(cache_key)
      return unless rate

      rate.success? ? handle_success(rate, cache_key) : handle_error(rate, cache_key)
    end

    def call_api(cache_key)
      RateApiClient.get_rate(period: @period, hotel: @hotel, room: @room)
    rescue StandardError => e
      errors << "Could not reach the pricing model: #{e.message}"
      log_event(:error, "api_unreachable", key: cache_key, error: e.message)
      nil
    end

    def handle_success(rate, cache_key)
      parsed_rate = parse_json_object(rate.body)
      unless parsed_rate
        errors << "Pricing model returned an unexpected response"
        log_event(:error, "unparseable_response", key: cache_key)
        return
      end

      result = extract_rate(parsed_rate)
      unless result
        errors << "No rate found for the given parameters"
        log_event(:error, "no_matching_rate", key: cache_key)
        return
      end

      log_event(:info, "cache_write", key: cache_key, ttl: CACHE_TTL.to_i)
      result
    end

    def handle_error(rate, cache_key)
      parsed = parse_json_object(rate.body)
      message = parsed&.dig("error") || "Pricing model returned an error"
      errors << message
      log_event(:error, "api_error", key: cache_key, message: message)
      nil
    end

    def extract_rate(parsed_rate)
      rates = parsed_rate["rates"]
      return nil unless rates.is_a?(Array)

      rates.detect do |r|
        r.is_a?(Hash) && r["period"] == @period && r["hotel"] == @hotel && r["room"] == @room
      end&.dig("rate")
    end

    def parse_json_object(body)
      parsed = JSON.parse(body)
      parsed.is_a?(Hash) ? parsed : nil
    rescue JSON::ParserError, TypeError
      nil
    end
  end
end
