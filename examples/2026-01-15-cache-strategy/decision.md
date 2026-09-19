> **DRAFT - synthesized jointly by Codex (example-model) + Claude Code (example-model); needs user confirmation before it is treated as the final decision.**

The question was whether the hot catalog endpoint should get a shared Redis cache or a per-instance in-process LRU cache.

## Agreement

Both reviewers recommend the in-process LRU with a short TTL (30 s) and reject Redis for now: the read path is one indexed SELECT, writes are about 200 per day, ADR 0007 asks for measured need before new infrastructure, and the 60 s staleness budget is compatible with a 30 s TTL.

## Disagreements

Not a disagreement but a difference in coverage: Claude Code raised cold-start load after a deploy and the cost of cross-instance inconsistency; Codex raised the stampede on hot-key expiry and the limits of write invalidation across six replicas. Both are valid and complementary. On invalidation the weight of evidence favours treating the TTL as the only real guarantee: with six instances and no broadcast, local invalidation only reaches the writing instance.

## Decision

Implement an in-process LRU (bounded size, TTL 30 s) for `GET /catalog/{id}` with single-flight loading, and expose a hit-rate metric. Do not add Redis. Revisit only if the measured hit rate is low or users see inconsistent versions.

## Minimal experiment that could refute the decision

Replay one hour of production read traffic against one instance with the cache enabled. If the hit rate is below 50% or p95 does not drop meaningfully, the premise (skewed reads) is wrong and the decision should be reconsidered.

## Experiment results

_The experiment has not been run yet._

## Authorized code changes

- `api/catalog.py`: wrap the read in a bounded LRU keyed by product id, TTL 30 s, single-flight on miss.
- `api/metrics.py`: add hit/miss counters.
- Forbidden: any new infrastructure or dependency, any change to write paths beyond a local cache invalidation call, any change to other endpoints.
