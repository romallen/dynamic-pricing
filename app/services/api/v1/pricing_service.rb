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
        Rails.logger.info "Cache hit for key=#{cache_key}"
        @result = cached_rate
        return
      end

      Rails.logger.info "Cache miss for key=#{cache_key}, fetching from API"
      begin
        rate = RateApiClient.get_rate(period: @period, hotel: @hotel, room: @room)
      rescue StandardError => e
        errors << "Could not reach the pricing model: #{e.message}"
        Rails.logger.error "Network error: #{e.message} (key=#{cache_key})"
        return
      end

      if rate.success?
        begin
          parsed_rate = JSON.parse(rate.body)
        rescue JSON::ParserError
          errors << "Pricing model returned an unexpected response"
          Rails.logger.error "JSON parse error (key=#{cache_key})"
          return
        end

        @result = parsed_rate['rates'].detect { |r| r['period'] == @period && r['hotel'] == @hotel && r['room'] == @room }&.dig('rate')

        if @result.nil?
          errors << "No rate found for the given parameters"
          Rails.logger.error "No matching rate in response (key=#{cache_key})"
          return
        end

        Rails.cache.write(cache_key, @result, expires_in: CACHE_TTL)
        Rails.logger.info "Cached rate for key=#{cache_key}, expires_in=#{CACHE_TTL}"
      else
        begin
          parsed_error = JSON.parse(rate.body)
          errors << (parsed_error['error'] || "Pricing model returned an error")
        rescue JSON::ParserError
          errors << "Pricing model returned an error"
        end
        Rails.logger.error "API error: #{errors.last} (key=#{cache_key})"
      end
    end
  end
end
