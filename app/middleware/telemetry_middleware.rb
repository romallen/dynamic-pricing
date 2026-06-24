class TelemetryMiddleware
  REQUEST_SPAN_NAME = "http.request".freeze
  ENABLED = ActiveModel::Type::Boolean.new.cast(ENV.fetch("OTEL_ENABLED", false))

  def self.configure_otel
    return if @configured

    @configured = true
    return unless ENABLED

    begin
      require "opentelemetry/sdk"
      require "opentelemetry/exporter/otlp"
      require "opentelemetry/instrumentation/all"
    rescue StandardError => e
      warn "[otel] traces disabled: #{e.class}: #{e.message}"
      return
    end

    OpenTelemetry::SDK.configure do |c|
      c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "dynamic-pricing")
      c.use_all
    end

    configure_metrics
  end

  def self.configure_metrics
    require "opentelemetry-metrics-sdk"
    require "opentelemetry-exporter-otlp-metrics"
    OpenTelemetry.meter_provider.add_metric_reader(
      OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
        exporter: OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter.new
      )
    )
  rescue StandardError => e
    warn "[otel] metrics disabled: #{e.class}: #{e.message}"
  end

  def initialize(app)
    @app = app
    self.class.configure_otel
  end

  def call(env)
    req = Rack::Request.new(env)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    Telemetry.span(REQUEST_SPAN_NAME, attributes: span_attributes(req)) do |span|
      status, headers, body = @app.call(env)
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      span&.set_attribute("http.status_code", status)
      span&.set_attribute("http.route", route_name(env)) if route_name(env)

      Telemetry.record_request(duration_s: duration, status_code: status, result: status < 400 ? "success" : "error")

      log_request(req, status, duration)
      [status, headers, body]
    end
  end

  private

  def span_attributes(req)
    {
      "http.method" => req.request_method,
      "http.scheme" => req.scheme,
      "http.target" => req.fullpath,
      "http.host" => req.host,
      "app.endpoint" => req.path_info
    }.compact
  end

  def route_name(env)
    path_params = env["action_dispatch.request.path_parameters"]
    return unless path_params.is_a?(Hash)

    controller = path_params[:controller]
    action = path_params[:action]
    return unless controller && action

    "#{controller}##{action}"
  end

  def log_request(req, status, duration)
    Rails.logger.info(
      "[Telemetry] event=request_complete " \
      "method=#{req.request_method} " \
      "path=#{req.path} " \
      "status=#{status} " \
      "duration=#{format('%.3f', duration)}"
    )
  end
end
