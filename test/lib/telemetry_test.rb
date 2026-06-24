require "test_helper"

# OTEL is off in tests — everything must be a safe no-op.
class TelemetryTest < ActiveSupport::TestCase
  test "span yields the block and returns its value when tracing is off" do
    yielded = false
    result = Telemetry.span("test") do
      yielded = true
      42
    end

    assert yielded, "block should run even when OpenTelemetry is not configured"
    assert_equal 42, result
  end

  test "metric recorders are no-ops when disabled" do
    assert_nothing_raised do
      Telemetry.record_cache("hit")
      Telemetry.record_upstream(duration_s: 0.01, error: false)
    end
  end
end
