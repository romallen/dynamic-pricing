require "test_helper"

class Api::V1::PricingControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
  end

  test "returns a rate for valid parameters" do
    stub_rate_api(mock_api_response(rate: "15000")) do
      get api_v1_pricing_url, params: { period: "Summer", hotel: "FloatingPointResort", room: "SingletonRoom" }

      assert_response :success
      assert_equal "application/json", @response.media_type
      assert_equal "15000", json_body["rate"]
    end
  end

  test "returns 400 when the pricing API returns an error" do
    stub_rate_api(mock_api_error_response(message: "Rate not found")) do
      get api_v1_pricing_url, params: { period: "Summer", hotel: "FloatingPointResort", room: "SingletonRoom" }

      assert_response :bad_request
      assert_includes json_body["error"], "Rate not found"
    end
  end

  test "returns 400 when all parameters are missing" do
    get api_v1_pricing_url

    assert_response :bad_request
    assert_includes json_body["error"], "Missing required parameters"
  end

  test "returns 400 when parameters are empty strings" do
    get api_v1_pricing_url, params: { period: "", hotel: "", room: "" }

    assert_response :bad_request
    assert_includes json_body["error"], "Missing required parameters"
  end

  test "rejects an invalid period" do
    get api_v1_pricing_url, params: { period: "summer-2024", hotel: "FloatingPointResort", room: "SingletonRoom" }

    assert_response :bad_request
    assert_includes json_body["error"], "Invalid period"
  end

  test "rejects an invalid hotel" do
    get api_v1_pricing_url, params: { period: "Summer", hotel: "InvalidHotel", room: "SingletonRoom" }

    assert_response :bad_request
    assert_includes json_body["error"], "Invalid hotel"
  end

  test "rejects an invalid room" do
    get api_v1_pricing_url, params: { period: "Summer", hotel: "FloatingPointResort", room: "InvalidRoom" }

    assert_response :bad_request
    assert_includes json_body["error"], "Invalid room"
  end

  test "returns 400 when the network is unreachable" do
    stub_rate_api_down do
      get api_v1_pricing_url, params: { period: "Summer", hotel: "FloatingPointResort", room: "SingletonRoom" }

      assert_response :bad_request
      assert_includes json_body["error"], "Could not reach the pricing model"
    end
  end

  test "returns 400 when API responds but no rate matches the parameters" do
    empty_rates = OpenStruct.new(success?: true, body: { "rates" => [] }.to_json)
    stub_rate_api(empty_rates) do
      get api_v1_pricing_url, params: { period: "Summer", hotel: "FloatingPointResort", room: "SingletonRoom" }

      assert_response :bad_request
      assert_includes json_body["error"], "No rate found"
    end
  end

  test "second identical request is served from cache without calling the API again" do
    api_call_count = 0
    counting_stub  = ->(**) { api_call_count += 1; mock_api_response }

    stub_rate_api(counting_stub) do
      2.times do
        get api_v1_pricing_url, params: { period: "Summer", hotel: "FloatingPointResort", room: "SingletonRoom" }
        assert_response :success
      end

      assert_equal 1, api_call_count, "Both requests have the same params so the second should be a cache hit"
    end
  end

  test "whitespace-only params are treated as missing" do
    get api_v1_pricing_url, params: { period: "   ", hotel: "FloatingPointResort", room: "SingletonRoom" }

    assert_response :bad_request
    assert_includes json_body["error"], "Missing required parameters"
  end

  test "period validation is case-sensitive" do
    get api_v1_pricing_url, params: { period: "summer", hotel: "FloatingPointResort", room: "SingletonRoom" }

    assert_response :bad_request
    assert_includes json_body["error"], "Invalid period"
  end

  private

  # Parses the JSON response body once and returns it as a Ruby hash.
  def json_body
    JSON.parse(@response.body)
  end
end
