# SDK init is lazy inside TelemetryMiddleware — only loads when OTEL_ENABLED=true.
require Rails.root.join("app/middleware/telemetry_middleware").to_s
Rails.application.config.middleware.use TelemetryMiddleware
