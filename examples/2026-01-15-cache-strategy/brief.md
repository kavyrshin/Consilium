# Brief: Cache strategy for the catalog API

**Date:** 2026-01-15
**Format:** manual consilium (no coordinator).
**Roles this round:** Independent reviewers (read-only): Claude Code (host), Codex. Draft decision synthesized by: Codex, Claude Code. Implementation: Claude Code. Verification: Codex. The final arbiter is the human, not a model.

## Question

`GET /catalog/{id}` is our hottest endpoint and p95 latency has crept up. Should we add a shared Redis cache in front of the database, or an in-process LRU cache per API instance?

## Known facts and source references

- `api/catalog.py:41` - every request runs one indexed SELECT, about 4 ms at p50 and 38 ms at p95 under load.
- `deploy/api.yaml:12` - 6 API replicas, no sticky sessions.
- `docs/decisions/0007-no-new-infra.md` - an earlier decision asks to avoid new infrastructure without a measured need.
- `api/catalog.py:88` - product updates come from an internal admin tool, roughly 200 writes per day.

## Constraints

- Reviewers are read-only during analysis.
- Any destructive or production action, and any merge to the main branch, needs the user's explicit approval.
- Stale reads must not exceed 60 seconds.

## Success criterion

The consilium is useful if, after the reviews, either (a) the approach proposed in the question is confirmed by the reviewers without changes, or (b) at least one review finds a concrete fact, risk or alternative that changes the decision. If no review adds anything beyond what is already known here, that is also a valid, though less valuable, outcome and is recorded in `decision.md` as it is.

## Out of scope

- Caching other endpoints.
- Changing the database schema or indexes.

## Response format

Each reviewer writes their own file in this folder (`<name>-review.md`) with exactly these sections:

```md
## Verdict
## Confirmed facts
## Assumptions and unknowns
## Risks and counter-arguments
## Recommendation
## What to check before implementing
```

Do not read other reviewers' files before your own is written. At most two rounds of discussion before `decision.md`.
