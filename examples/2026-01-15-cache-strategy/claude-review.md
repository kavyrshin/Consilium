# Claude Code review (example-model): Cache strategy for the catalog API

## Verdict

Start with the in-process LRU with a short TTL; do not add Redis yet.

## Confirmed facts

- The query is a single indexed SELECT (`api/catalog.py:41`); the tail latency is a load effect, not a slow query.
- Writes are rare (about 200/day, `api/catalog.py:88`), so almost every read is cacheable.
- ADR 0007 requires a measured need before new infrastructure.

## Assumptions and unknowns

- Assumed the 38 ms p95 comes from connection-pool contention rather than the query itself; not measured.
- Unknown: how skewed the traffic is. An LRU only helps if a small set of products gets most reads.

## Risks and counter-arguments

- With 6 replicas and no stickiness, per-instance caches are inconsistent with each other. With a 60 s TTL this stays inside the staleness budget, but two consecutive requests can return different versions.
- Cold start after a deploy empties every cache at once and briefly raises database load.
- Redis would give one consistent view and explicit invalidation, at the cost of a new dependency and a new failure mode.

## Recommendation

In-process LRU, TTL 30 s, bounded size, plus a metrics counter for hit rate. Revisit Redis only if the hit rate is poor or inconsistency shows up in practice.

## What to check before implementing

- Read traffic distribution: share of requests hitting the top 1% of product ids.
- Whether p95 is driven by pool wait time, from database metrics.
