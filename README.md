# Dynamic Pricing Proxy

Caches rate-api responses. Same period/hotel/room in the next 5 minutes? Cache hit, no upstream call.

## Quick Start

```bash
rake docker:build   # build image and start both services
rake docker:start   # start if already built
rake docker:stop

rake docker:test
rake docker:lint
rake docker:typecheck
```

```bash
curl 'http://localhost:3000/api/v1/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom'
```

| Parameter | Options |
|-----------|---------|
| `period`  | `Summer`, `Autumn`, `Winter`, `Spring` |
| `hotel`   | `FloatingPointResort`, `GitawayHotel`, `RecursionRetreat` |
| `room`    | `SingletonRoom`, `BooleanTwin`, `RestfulKing` |

---

## How it works

rate-api gives 1,000 calls/day. The service needs to handle 10,000+. Without a cache, the quota is gone after the first 10% of traffic.

Requests hit `PricingController` (validates params against fixed allowlists) then `PricingService`. The service calls `Rails.cache.fetch` with a 5-minute TTL. Cache hit returns immediately. On a miss, it calls rate-api, caches the result, and returns it. `race_condition_ttl: 5` prevents expiry stampedes. `skip_nil: true` means errors never get cached — a failed call returns a 400 and the next request retries fresh.

**Why MemoryStore:** ships with Rails, no extra services needed. The cache resets on restart, but with a 5-minute TTL that costs at most one extra API call per combination. Scaling to multiple hosts means swapping to `:redis_cache_store` — `PricingService` doesn't change.

---

## Observability

**Logs.** Every request and cache event emits a JSON line via `lograge` + `Rails.logger`, ready for Elastic, Datadog, or any collector that reads Docker stdout:

```json
{"method":"GET","path":"/api/v1/pricing","status":200,"duration":8.07,...}
{"service":"PricingService","event":"cache_miss","key":"pricing/Summer/FloatingPointResort/SingletonRoom"}
{"service":"PricingService","event":"api_unreachable","key":"...","error":"connection refused"}
```

**Traces and metrics.** OpenTelemetry is off by default — set `OTEL_ENABLED=true` in `.env` to turn it on. `TelemetryMiddleware` wraps every request in an `http.request` span with auto-instrumented child spans for Rails routing and the Net::HTTP call to rate-api. All endpoints get traces and metrics automatically. Four metrics: `http.server.requests`, `http.server.duration`, `pricing.cache.requests`, `pricing.upstream.duration`.

| Var | Default | What it does |
|-----|---------|--------------|
| `OTEL_ENABLED` | `false` | Master switch |
| `OTEL_SERVICE_NAME` | `dynamic-pricing` | Service name |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318` | Collector endpoint |
| `OTEL_TRACES_EXPORTER` | `otlp` | Set to `console` to print spans locally |

---

## Tests

```bash
rake docker:test       # 38 tests, 105 assertions
rake docker:lint       # RuboCop
rake docker:typecheck  # RBS signatures
```

---

## Production readiness

Things added beyond the core caching requirement:

- **HTTP timeout.** `default_timeout 3` on the HTTParty client. A slow rate-api response can't tie up a Puma thread indefinitely. Raises `Net::ReadTimeout`, caught and returned as a 400.
- **Stampede protection.** `race_condition_ttl: 5` on every `cache.fetch`. When a key expires under load, one thread regenerates it while the rest briefly serve the stale value.
- **Error isolation.** `skip_nil: true` means failed and malformed API responses are never written to the cache. The next request always gets a fresh attempt.
- **Input validation.** Controller validates all three params against fixed allowlists before the service runs. Invalid params return 400 immediately — nothing reaches the cache or the upstream.
- **Structured JSON logging.** `lograge` replaces Rails' multi-line request logs with a single JSON line per request. Service events (cache hit/miss, upstream errors) also emit JSON. Both are Elastic/Datadog-compatible out of the box — any collector reading Docker stdout can ingest them.
- **OpenTelemetry.** Traces and metrics via `TelemetryMiddleware`. Off by default, zero overhead when disabled. Covers all endpoints automatically — no per-controller instrumentation needed.
- **CI.** GitHub Actions runs tests, lint, and type checks on every push.
- **Dependabot.** Weekly automated PRs for gem, Docker, and Actions updates.
- **Secrets management.** `.env` for local dev. `config/initializers/secrets.rb` loads from AWS Secrets Manager in production when `SECRETS_ARN` is set.

---

## Future improvements

- **Shared cache.** Swap MemoryStore for Redis or Valkey. Required for multi-host deployments or multiple Puma workers sharing state. `PricingService` doesn't change.
- **Circuit breaker.** If rate-api goes down, every cache miss hammers it. A circuit breaker (e.g. `stoplight`) opens after N consecutive failures and short-circuits during a cooldown window.
- **Quota tracking.** Rolling counter of upstream calls with an alert at ~80% of the 1,000/day cap. You want to know before requests start failing, not after.
- **Telemetry backend.** The app emits JSON logs, OTel traces, and OTel metrics. Production needs a collector (Filebeat/Fluentd for logs, OTel Collector for traces/metrics) and dashboards — cache hit rate, upstream latency, error rate. Grafana/Tempo or Datadog both work with OTLP.
- **Deeper health check.** `/up` confirms the process is alive. A `/healthz` that verifies the cache store is reachable gives load balancers better signal.

---

## AI assistance

I used Claude Code throughout — design, implementation, tests. I directed the decisions and own the approach.
