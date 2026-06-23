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

  private

  # Parses the JSON response body once and returns it as a Ruby hash.
  def json_body
    JSON.parse(@response.body)
  end
end
