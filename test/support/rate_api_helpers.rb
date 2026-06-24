# Shared test helpers for anything that touches the rate API or PricingService.
# Included in ActiveSupport::TestCase via test_helper.rb, so every test class
# can use these without requiring anything extra.
module RateApiHelpers
  VALID_PERIODS = Api::V1::PricingController::VALID_PERIODS
  VALID_HOTELS  = Api::V1::PricingController::VALID_HOTELS
  VALID_ROOMS   = Api::V1::PricingController::VALID_ROOMS

  # Sensible defaults so individual tests only have to specify what they care about.
  DEFAULT_PERIOD = "Summer".freeze
  DEFAULT_HOTEL  = "FloatingPointResort".freeze
  DEFAULT_ROOM   = "SingletonRoom".freeze
  DEFAULT_RATE   = "15000".freeze

  # Builds a fake HTTP response that looks like a successful rate API reply.
  # The body is a JSON string — matching what HTTParty actually returns.
  def mock_api_response(period: DEFAULT_PERIOD, hotel: DEFAULT_HOTEL, room: DEFAULT_ROOM, rate: DEFAULT_RATE)
    body = {
      "rates" => [
        { "period" => period, "hotel" => hotel, "room" => room, "rate" => rate }
      ]
    }.to_json
    OpenStruct.new(success?: true, body: body)
  end

  # Builds a fake HTTP failure response (4xx/5xx).
  def mock_api_error_response(message: "Rate not found")
    OpenStruct.new(success?: false, body: { "error" => message }.to_json)
  end

  # Builds a successful response where the rates array is empty (no matching rate).
  def mock_empty_rates_response
    OpenStruct.new(success?: true, body: { "rates" => [] }.to_json)
  end

  # Stubs RateApiClient.get_rate for the duration of the block.
  # Pass any object as `response` — an OpenStruct, a lambda, etc.
  def stub_rate_api(response, &)
    RateApiClient.stub(:get_rate, response, &)
  end

  # Stubs RateApiClient.get_rate to raise a network-level error.
  def stub_rate_api_down(message: "connection refused", &)
    RateApiClient.stub(:get_rate, ->(**) { raise StandardError, message }, &)
  end

  # Instantiates PricingService, calls run, and returns the service object.
  # Useful when you only care about the result, not the setup boilerplate.
  def run_pricing_service(period: DEFAULT_PERIOD, hotel: DEFAULT_HOTEL, room: DEFAULT_ROOM)
    service = Api::V1::PricingService.new(period: period, hotel: hotel, room: room)
    service.run
    service
  end
end
