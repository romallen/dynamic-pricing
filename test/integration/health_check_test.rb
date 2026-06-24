require "test_helper"

class HealthCheckTest < ActionDispatch::IntegrationTest
  test "GET /up returns success when the app is booted" do
    get "/up"

    assert_response :success
  end
end
