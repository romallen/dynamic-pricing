# No-op when OTEL_ENABLED is false — SDK never loads, every method is safe to call.
module Telemetry
  NAME = "dynamic-pricing".freeze

  class << self
    def span(name, attributes: {}, &)
      return yield(nil) unless tracing?

      OpenTelemetry.tracer_provider.tracer(NAME).in_span(name, attributes: attributes, &)
    end

    def record_cache(result)
      cache_counter&.add(1, attributes: { "result" => result })
    end

    def record_upstream(duration_s:, error:)
      upstream_duration&.record(duration_s, attributes: { "error" => error })
    end

    def record_request(duration_s:, status_code:, result:)
      request_counter&.add(1, attributes: { "http.status_code" => status_code, "result" => result })
      request_duration&.record(duration_s, attributes: { "http.status_code" => status_code, "result" => result })
    end

    private

    def tracing?
      defined?(OpenTelemetry) && OpenTelemetry.respond_to?(:tracer_provider)
    end

    def meter
      return nil unless defined?(OpenTelemetry) && OpenTelemetry.respond_to?(:meter_provider)

      @meter ||= OpenTelemetry.meter_provider.meter(NAME)
    end

    def cache_counter
      @cache_counter ||= meter&.create_counter(
        "pricing.cache.requests", description: "Cache lookups by result (hit/miss)", unit: "1"
      )
    end

    def upstream_duration
      @upstream_duration ||= meter&.create_histogram(
        "pricing.upstream.duration", description: "rate-api call duration", unit: "s"
      )
    end

    def request_counter
      @request_counter ||= meter&.create_counter(
        "http.server.requests", description: "HTTP requests by status and result", unit: "1"
      )
    end

    def request_duration
      @request_duration ||= meter&.create_histogram(
        "http.server.duration", description: "HTTP request duration", unit: "s"
      )
    end
  end
end
