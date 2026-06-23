<div align="center">
   <img src="/img/logo.svg?raw=true" width=600 style="background-color:white;">
</div>

# Dynamic Pricing Proxy — Solution

## Quick Start

```bash
# Build and start both services (Rails app + rate-api)
docker compose up -d --build

# Hit the endpoint
curl 'http://localhost:3000/api/v1/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom'

# Run the test suite
docker compose exec interview-dev ./bin/rails test

# Run the linter
docker compose exec interview-dev bundle exec rubocop
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

I added a caching layer inside `PricingService` using `Rails.cache.read` and `Rails.cache.write`. The flow is:

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

### Error handling

The rate-api docs do not specify an error response format, so the service handles all failure modes defensively:

- **Network error** (timeout, connection refused): returns a descriptive 400 with the error message.
- **API error response** (non-2xx): attempts to parse `{ "error": "..." }` from the body; falls back to a generic message if the body is not valid JSON or has no `error` key.
- **Rate found but no match**: if the API responds successfully but the returned rates don't include the requested combination, returns a 400 rather than silently serving a nil rate.

In all error cases, nothing is written to the cache — the next request retries the API fresh.

---

## Assumptions

- A failed API call returns an error to the user immediately. Stale cached data is **never** served — an outdated rate could cause incorrect pricing, which is worse than a temporary error.
- The valid values for `period`, `hotel`, and `room` are fixed (as defined in the scaffold).
- Single-instance deployment. `MemoryStore` is not shared across multiple processes; a multi-process or multi-host deployment would need a shared cache (e.g. Redis).
- The 1,000/day quota resets when the `rate-api` Docker container is restarted (per the Docker Hub docs). In production, assume the quota is a hard rolling-24-hour limit.

---

## Code Quality

### Linter

[RuboCop](https://rubocop.org) with the `rubocop-rails` and `rubocop-minitest` extensions enforces style consistency:

```bash
docker compose exec interview-dev bundle exec rubocop
```

### Type signatures

RBS type signatures live in `sig/`. They document the public interface of the service and client classes without requiring a type-checking runtime in the hot path:

```bash
# View signatures
cat sig/api/v1/pricing_service.rbs
```

### Tests

```bash
docker compose exec interview-dev ./bin/rails test
```

---

## AI Assistance

This solution was developed with Claude Code (Anthropic) as an AI coding assistant. Claude was used for:

- Exploring the existing scaffold and rate-api Docker Hub documentation
- Designing the caching strategy and tradeoff analysis
- Writing the implementation across `PricingService` and the test suite
- Setting up RuboCop and RBS type signatures

All code was reviewed and understood before submission. The design choices and tradeoffs above reflect my own reasoning.
