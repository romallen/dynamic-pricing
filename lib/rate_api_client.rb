class RateApiClient
  include HTTParty

  base_uri ENV.fetch("RATE_API_URL", "http://localhost:8080")
  headers "Content-Type" => "application/json"
  headers "token" => ENV.fetch("RATE_API_TOKEN")
  # Bound a slow upstream so it can't tie up a Puma thread. A timeout raises
  # Net::ReadTimeout, which PricingService#call_api rescues into a clean 400.
  default_timeout Integer(ENV.fetch("RATE_API_TIMEOUT", 15))

  def self.get_rate(period:, hotel:, room:)
    params = {
      attributes: [
        {
          period: period,
          hotel: hotel,
          room: room
        }
      ]
    }.to_json
    post("/pricing", body: params)
  end
end
