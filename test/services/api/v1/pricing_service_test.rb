require "test_helper"

class Api::V1::PricingServiceTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Rails.cache.clear
  end

  test "cache miss: calls the API and stores the result" do
    stub_rate_api(mock_api_response) do
      service = run_pricing_service

      assert_predicate service, :valid?
      assert_equal DEFAULT_RATE, service.result

      cached = Rails.cache.read("pricing/#{DEFAULT_PERIOD}/#{DEFAULT_HOTEL}/#{DEFAULT_ROOM}")

      assert_equal DEFAULT_RATE, cached
    end
  end

  test "cache hit: returns cached result without calling the API again" do
    api_call_count = 0
    counting_stub  = lambda { |**|
      api_call_count += 1
      mock_api_response
    }

    stub_rate_api(counting_stub) do
      run_pricing_service  # populates cache
      run_pricing_service  # should come from cache

      assert_equal 1, api_call_count, "API should only be called once; second request should use the cache"
    end
  end

  test "network error: adds a descriptive message" do
    stub_rate_api_down do
      service = run_pricing_service

      assert_not service.valid?
      assert_includes service.errors.first, "Could not reach the pricing model"
    end
  end

  test "API error response: adds the error from the response body" do
    stub_rate_api(mock_api_error_response(message: "Rate not found")) do
      service = run_pricing_service

      assert_not service.valid?
      assert_includes service.errors.first, "Rate not found"
    end
  end

  test "rate not found in response: adds an error and does not cache" do
    empty_rates = OpenStruct.new(success?: true, body: { "rates" => [] }.to_json)
    stub_rate_api(empty_rates) do
      service = run_pricing_service

      assert_not service.valid?
      assert_includes service.errors.first, "No rate found"

      cached = Rails.cache.read("pricing/#{DEFAULT_PERIOD}/#{DEFAULT_HOTEL}/#{DEFAULT_ROOM}")

      assert_nil cached, "Error results must never be written to the cache"
    end
  end

  test "different param combinations use separate cache entries" do
    api_call_count = 0
    counting_stub  = lambda { |**kw|
      api_call_count += 1
      mock_api_response(**kw.slice(:period, :hotel, :room))
    }

    stub_rate_api(counting_stub) do
      run_pricing_service(period: "Summer", hotel: "FloatingPointResort", room: "SingletonRoom")
      run_pricing_service(period: "Summer", hotel: "FloatingPointResort", room: "BooleanTwin")

      assert_equal 2, api_call_count, "Each unique param combination should have its own cache entry"
    end
  end

  test "failed requests are not cached: next request retries the API" do
    api_call_count = 0

    stub_rate_api(lambda { |**|
      api_call_count += 1
      mock_api_error_response
    }) do
      run_pricing_service
    end

    stub_rate_api(lambda { |**|
      api_call_count += 1
      mock_api_response
    }) do
      service = run_pricing_service

      assert_predicate service, :valid?, "Expected valid result on retry after previous failure"
      assert_equal DEFAULT_RATE, service.result
      assert_equal 2, api_call_count, "API should have been called twice (once for each attempt)"
    end
  end

  # ---------------------------------------------------------------------------
  # Cache TTL
  # ---------------------------------------------------------------------------

  test "cache expires after TTL and triggers a fresh API call" do
    api_call_count = 0
    counting_stub  = lambda { |**|
      api_call_count += 1
      mock_api_response
    }

    stub_rate_api(counting_stub) do
      run_pricing_service # populates cache

      # Jump past the 5-minute window — the cached entry should now be stale
      travel Api::V1::PricingService::CACHE_TTL + 1.second do
        run_pricing_service
      end

      assert_equal 2, api_call_count, "Cache should expire after #{Api::V1::PricingService::CACHE_TTL}, forcing a fresh API call"
    end
  end

  # ---------------------------------------------------------------------------
  # Malformed / unexpected API responses
  # ---------------------------------------------------------------------------

  test "malformed JSON in success response: adds error" do
    stub_rate_api(OpenStruct.new(success?: true, body: "not-valid-json")) do
      service = run_pricing_service

      assert_not service.valid?
      assert_includes service.errors.first, "unexpected response"
    end
  end

  test "API error with non-JSON body: uses fallback message" do
    stub_rate_api(OpenStruct.new(success?: false, body: "<html>500 Internal Server Error</html>")) do
      service = run_pricing_service

      assert_not service.valid?
      assert_includes service.errors.first, "Pricing model returned an error"
    end
  end

  test "API error without error key in body: uses fallback message" do
    stub_rate_api(OpenStruct.new(success?: false, body: { "message" => "something went wrong" }.to_json)) do
      service = run_pricing_service

      assert_not service.valid?
      assert_includes service.errors.first, "Pricing model returned an error"
    end
  end

  # ---------------------------------------------------------------------------
  # Data-driven: spot-check several valid param combinations
  # ---------------------------------------------------------------------------

  [
    %w[Summer FloatingPointResort SingletonRoom],
    %w[Winter GitawayHotel BooleanTwin],
    %w[Autumn RecursionRetreat RestfulKing],
    %w[Spring FloatingPointResort BooleanTwin]
  ].each do |period, hotel, room|
    test "fetches and caches rate for #{period}/#{hotel}/#{room}" do
      stub_rate_api(mock_api_response(period: period, hotel: hotel, room: room, rate: "20000")) do
        service = run_pricing_service(period: period, hotel: hotel, room: room)

        assert_predicate service, :valid?
        assert_equal "20000", service.result
        assert_equal "20000", Rails.cache.read("pricing/#{period}/#{hotel}/#{room}")
      end
    end
  end
end
