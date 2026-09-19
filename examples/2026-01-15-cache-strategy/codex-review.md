# Codex review (example-model): Cache strategy for the catalog API

## Verdict

An in-process cache is enough now. Add invalidation on write so the TTL is a backstop, not the mechanism.

## Confirmed facts

- Six replicas, no sticky sessions (`deploy/api.yaml:12`).
- The admin write path is a single place (`api/catalog.py:88`), so invalidation has one hook point.

## Assumptions and unknowns

- Assumed the admin tool talks to the same API fleet; if it uses a separate service, a write there cannot invalidate the local caches.

## Risks and counter-arguments

- Without invalidation the 60 s budget is used up on every write; with per-instance caches and no broadcast, invalidation only reaches the instance that handled the write.
- A cache stampede on a hot key when its TTL expires: add request coalescing (single flight).

## Recommendation

In-process LRU with TTL 30 s, single-flight loading for misses, and local invalidation on write. Redis is not justified by the facts here.

## What to check before implementing

- Which process handles admin writes.
- Memory headroom per replica for the chosen cache size.
