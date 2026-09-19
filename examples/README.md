# Example case

`2026-01-15-cache-strategy/` shows what a case folder contains after a consilium: the brief, two reviews and the draft decision.

**This example was written by hand to illustrate the format. It is not real model output**, and the facts, file names and numbers in it are invented. A real run also leaves `.logs/`, `.runners/` and `.watch.log` (git-ignored by default), plus `tasks.json`, and after implementation `impl-report.md`, `<name>-impl-review.md` and `fix-report.md`.

Try the machinery yourself without any model:

```bash
mkdir demo && cd demo && git init -q
export CM_HOST=me CM_REVIEWERS=mock CM_ARBITERS=mock
bash ../skills/consilium/scripts/init-case.sh cache-strategy "Cache strategy"
```
