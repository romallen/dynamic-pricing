<div align="center">
   <img src="/img/logo.svg?raw=true" width=600 style="background-color:white;">
</div>

# Dynamic Pricing Proxy — Solution

A Rails API that fronts an expensive pricing model and caches each rate for the
5 minutes it stays valid. Fetch a price for a given period/hotel/room once, and
everyone asking for the same thing in the next 5 minutes gets that cached answer
instead of another upstream call.

## Quick Start

The `docker:*` rake tasks wrap `docker compose` and run from the host (outside
the container). Run `rake -T docker` to see the full list.

```bash
# Build the image and start both services (Rails app + rate-api)
rake docker:build
rake docker:start

# Hit the endpoint
curl 'http://localhost:3000/api/v1/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom'

# Run the tests
rake docker:test

# Lint and type-check
rake docker:lint
rake docker:typecheck

# Tail logs, open a console or a shell when you need them
rake docker:logs
rake docker:console
rake docker:shell

# Stop everything
rake docker:stop
```

The endpoint takes three parameters, each with a fixed set of valid values:

| Parameter | Options |
|-----------|---------|
| `period`  | `Summer`, `Autumn`, `Winter`, `Spring` |
| `hotel`   | `FloatingPointResort`, `GitawayHotel`, `RecursionRetreat` |
| `room`    | `SingletonRoom`, `BooleanTwin`, `RestfulKing` |

---

## How I thought about it

### The constraints

Two numbers from the [rate-api docs](https://hub.docker.com/r/tripladev/rate-api)
shaped everything: 1,000 calls/day on a single token, and a rate that's valid for
5 minutes. The service has to serve 10,000+ requests/day. Without caching, the
quota is gone in about two minutes — so the cache is the point of the exercise.

### What I built

The caching lives in `PricingService`. On each request I build a cache key from
`period/hotel/room`, read `Rails.cache`, and return the hit if it's there. On a
miss I call the rate-api, write the result with a 5-minute TTL, and return it.

It's a lazy cache — entries appear the first time something is asked for, nothing
is pre-warmed. I never cache errors, so a failed call retries cleanly next time
instead of pinning a failure in the cache for 5 minutes.

The cache key is just interpolated param values. That's safe here because the
controller validates all three params against fixed allowlists before the service
runs, so keys can't collide or be injected.

### Why MemoryStore

`MemoryStore` ships with Rails, needs no extra services, and is thread-safe, so it
holds up fine under Puma's threads. The catch is it's per-process and dies on
restart — but rates only live 5 minutes, so a restart costs at most one extra call
per combination. Redis would matter if this ran on more than one instance; for a
single instance it's just ops overhead. If this needed to scale out, swapping the
store for `:redis_cache_store` is the only change — the service code wouldn't move.

### Does it stay under budget?

Yes, with room to spare. There are only 36 possible combinations, and a warm key
needs at most one call every 5 minutes. Spread 10,000 requests across 36 keys and
you're nowhere near 1,000 calls/day — and real traffic skews toward a handful of
popular combinations that just stay hot.

The honest gap: on a cold key, concurrent requests can all miss and call the API
before the first one writes the cache (a cache stampede). With 36 keys and a
5-minute TTL it never threatens the budget, so I documented it instead of adding a
lock — and an in-process lock wouldn't help across processes anyway. The real fix
would be `race_condition_ttl` or a shared lock once there's a shared cache.

### When things go wrong

The docs don't define an error format, so the service handles failure without ever
returning a 500:

- **Can't reach the API** (timeout, refused) → 400 with a clear message.
- **API returns an error status** → pull `error` from the body, fall back to a
  generic message if the body is missing, not JSON, or not an object.
- **200 with a weird body** (valid JSON but wrong shape, `null`, an array, no
  `rates`) → 400 instead of a crash.
- **No matching rate in the response** → 400, not a silent nil.
- **Cache read/write fails** → logged and treated as best-effort; the request
  still answers from the API.

None of these get cached, so the next request always gets a clean retry.

### Observability

Cache and failure paths emit structured, logfmt-style lines so they're easy to
grep and parse:

```
[PricingService] event=cache_miss key="pricing/Summer/FloatingPointResort/SingletonRoom"
[PricingService] event=cache_write key="pricing/Summer/FloatingPointResort/SingletonRoom" ttl="300"
[PricingService] event=api_unreachable key="..." error="connection refused"
```

That makes cache hit-rate something you can actually compute from logs, and gives
you obvious events (`api_unreachable`, `api_error`) to alert on. There's also a
`GET /up` liveness endpoint for load balancers and uptime checks.

---

## Assumptions

- Better to return an error than serve a stale price — a wrong rate means charging
  the wrong amount, which is worse than a brief failure.
- The valid values for `period`, `hotel`, and `room` are fixed by the scaffold.
- Single instance. `MemoryStore` isn't shared across processes, so a multi-process
  or multi-host setup would need a shared cache like Redis.
- The 1,000/day quota resets when the rate-api container restarts (per the docs);
  in production I'd treat it as a hard rolling-24-hour limit.

---

## Tests, linting, types

- **Tests** — `rake docker:test`. Shared mocking helpers are in
  `test/support/rate_api_helpers.rb`; coverage runs from cache hit/miss and TTL
  expiry through network failures and malformed responses.
- **Linting** — RuboCop with the Rails, Minitest, and Performance cops: `rake docker:lint`.
- **Types** — RBS signatures in `sig/`, checked with `rake docker:typecheck`.

I also stripped the unused Rails scaffold — no ActiveRecord/SQLite, ActionCable, or
ActiveJob. It's a stateless proxy, so none of that was pulling weight.

---

## AI assistance

I used Claude Code (Anthropic) while building this — for exploring the scaffold and
the rate-api docs, working through the caching tradeoffs, and writing the
implementation and tests. I understand every line and the reasoning here is mine.
