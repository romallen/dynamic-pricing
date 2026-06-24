# Registers the request telemetry middleware. The actual OpenTelemetry SDK
# initialization is handled lazily inside `TelemetryMiddleware`, so the app
# only loads OTEL when OTEL_ENABLED is truthy.
require Rails.root.join("app/middleware/telemetry_middleware").to_s
Rails.application.config.middleware.use TelemetryMiddleware
