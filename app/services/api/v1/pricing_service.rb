module Api::V1
  class PricingService < BaseService
    CACHE_TTL = 5.minutes

    def initialize(period:, hotel:, room:)
      @period = period
      @hotel = hotel
      @room = room
    end

    def run
      cache_key = "pricing/#{@period}/#{@hotel}/#{@room}"

      cached_rate = Rails.cache.read(cache_key)
      if cached_rate
        @result = cached_rate
        return
      end

      begin
      rate = RateApiClient.get_rate(period: @period, hotel: @hotel, room: @room)
      rescue StandardError => e
        errors << "Could not reach the pricing model: #{e.message}"
        return
      end

      if rate.success?
        begin
        parsed_rate = JSON.parse(rate.body)
        rescue JSON::ParserError
          errors << "Pricing model returned an unexpected response"
          return
        end

        @result = parsed_rate['rates'].detect { |r| r['period'] == @period && r['hotel'] == @hotel && r['room'] == @room }&.dig('rate')

        if @result.nil?
          errors << "No rate found for the given parameters"
          return
        end

        Rails.cache.write(cache_key, @result, expires_in: CACHE_TTL)
      else
        begin
          parsed_error = JSON.parse(rate.body)
          errors << (parsed_error['error'] || "Pricing model returned an error")
        rescue JSON::ParserError
          errors << "Pricing model returned an error"
        end
      end
    end
  end
end
