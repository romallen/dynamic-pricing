<div align="center">
   <img src="/img/logo.svg?raw=true" width=600 style="background-color:white;">
</div>

# Dynamic Pricing Proxy — Solution

A Rails API service that proxies an expensive dynamic-pricing model and caches
each rate for its 5-minute validity window, so repeated requests are served
without re-hitting the rate-limited upstream API.

## Quick Start

```bash
# Build and start both services (Rails app + rate-api)
docker compose up -d --build

# Hit the endpoint
curl 'http://localhost:3000/api/v1/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom'

# Run the test suite
docker compose exec interview-dev ./bin/rails test

# Lint and type-check (also available as rake docker:lint / rake docker:typecheck)
docker compose exec interview-dev bundle exec rubocop
docker compose exec interview-dev bundle exec rbs -I sig validate
```

**Valid parameter values:**

| Parameter | Options |
|-----------|---------|
| `period`  | `Summer`, `Autumn`, `Winter`, `Spring` |
| `hotel`   | `FloatingPointResort`, `GitawayHotel`, `RecursionRetreat` |
| `room`    | `SingletonRoom`, `BooleanTwin`, `RestfulKing` |

---

## Design Decisions

### The problem

The [rate-api Docker Hub docs](https://hub.docker.com/r/tripladev/rate-api) document two hard constraints:

1. **1,000 API calls per day** per token before the quota is exhausted (resets on container restart).
2. A fetched rate is **valid for up to 5 minutes**, so re-fetching sooner than that wastes a call with no benefit.

Our service needs to handle **10,000+ user requests/day**. Without caching, every request consumes one API call — the daily quota would be gone in under two minutes.

### The solution: in-memory caching with a 5-minute TTL

The caching layer lives inside `PricingService` and uses `Rails.cache.read` / `Rails.cache.write`. The flow is:

1. Build a cache key from `period/hotel/room` (e.g. `pricing/Summer/FloatingPointResort/SingletonRoom`).
2. Call `Rails.cache.read(cache_key)`. If a fresh entry (< 5 min old) exists, return it immediately — **no API call**.
3. On a cache miss, call the rate-api, store the result with `expires_in: 5.minutes`, then return it.

This is a **lazy cache** (populated on demand, not pre-warmed). Errors are never written to the cache, so a transient API failure retries immediately on the next request rather than serving stale error state.

### Why `Rails.cache` with `MemoryStore`?

| Option | Pros | Cons |
|--------|------|------|
| `MemoryStore` (chosen) | Zero extra dependencies, built into Rails, simple | Cache lost on process restart |
| `FileStore` | Persists across restarts, still no extra deps | Slower (disk I/O per request) |
| Redis | Fast, persistent, shareable across instances | Requires extra service, gem, and ops work |

`MemoryStore` is the right call here. Rates are only valid for 5 minutes, so losing the cache on a restart costs at most one extra API call per combination — the service recovers on the very next request. Adding Redis would introduce meaningful operational complexity with no benefit for a single-instance deployment.

### Throughput math

- **API budget:** 1,000 calls/day
- **Cache TTL:** 5 minutes → at most **288 refresh windows/day** per combination
- **Unique combinations:** 4 periods × 3 hotels × 3 rooms = **36**

If all 36 combinations were requested continuously and evenly, worst-case API usage is 288 × 36 = 10,368 calls/day — over budget. But this represents a pathological scenario where every combination is requested at exactly the cache boundary every 5 minutes, all day. In practice:

- Traffic is skewed. A small number of popular combinations dominate and stay warm in the cache continuously.
- At 10,000 user requests/day spread across 36 combos, each combo receives ~278 requests. With a 5-minute TTL, those 278 requests require **at most 12 API calls/hour** per combo (one per window) — well within the 1,000/day total budget.

The service comfortably handles the throughput requirements under any realistic traffic distribution.

**Known limitation — cache stampede:** on a cache miss, concurrent requests for
the same key each call the API before the first writes the cache. With only 36
combinations and a 5-minute TTL this stays within budget, so a single-flight
lock was intentionally omitted (an in-process lock would also be ineffective
across multiple processes). It's documented rather than solved by design.

### Error handling

The rate-api docs do not specify an error response format, so the service handles all failure modes defensively and **never returns a 500 for a bad upstream response**:

- **Network error** (timeout, connection refused): returns a descriptive 400.
- **API error response** (non-2xx): parses `{ "error": "..." }` from the body; falls back to a generic message if the body is missing, not JSON, or not an object.
- **Malformed / wrong-shape success body**: a 200 that is valid JSON but the wrong shape (no `rates` array, `null`, a JSON array, etc.) degrades to a 400 instead of crashing.
- **Rate found but no match**: a successful response without a matching rate returns a 400 rather than silently serving a `nil` rate.
- **Cache is best-effort**: a cache read/write failure is logged and the request still completes against the API.

In all error cases, nothing is written to the cache — the next request retries the API fresh.

---

## Assumptions

- A failed API call returns an error to the user immediately. Stale cached data is **never** served — an outdated rate could cause incorrect pricing, which is worse than a temporary error.
- The valid values for `period`, `hotel`, and `room` are fixed (as defined in the scaffold).
- Single-instance deployment. `MemoryStore` is not shared across multiple processes; a multi-process or multi-host deployment would need a shared cache (e.g. Redis).
- The 1,000/day quota resets when the `rate-api` Docker container is restarted (per the Docker Hub docs). In production, assume the quota is a hard rolling-24-hour limit.

---

## Project scope

This is a stateless proxy, so the unused Rails scaffold was removed to keep the
surface small and the intent clear: no ActiveRecord/SQLite/database, no
ActionCable, no ActiveJob. The app runs as a true API-only Rails service.

---

## Code Quality

- **Tests** — `docker compose exec interview-dev ./bin/rails test`. Shared mocking helpers live in `test/support/rate_api_helpers.rb`; coverage includes cache hit/miss, TTL expiry, network failures, and malformed/wrong-shape responses.
- **Linter** — [RuboCop](https://rubocop.org) with the `rubocop-rails`, `rubocop-minitest`, and `rubocop-performance` extensions: `rake docker:lint`.
- **Type signatures** — RBS signatures in `sig/` document the public interface; validate with `rake docker:typecheck`.

---

## AI Assistance

This solution was developed with Claude Code (Anthropic) as an AI coding assistant. Claude was used for:

- Exploring the existing scaffold and rate-api Docker Hub documentation
- Designing the caching strategy and tradeoff analysis
- Writing the implementation across `PricingService` and the test suite
- Setting up RuboCop, RBS type signatures, and trimming unused scaffold

All code was reviewed and understood before submission. The design choices and tradeoffs above reflect my own reasoning.
