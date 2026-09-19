# Example case

`2026-01-15-cache-strategy/` shows what a case folder contains after a consilium: the brief, two reviews and the draft decision.

**This example was written by hand to illustrate the format. It is not real model output**, and the facts, file names and numbers in it are invented. A real run also leaves `.logs/`, `.runners/` and `.watch.log` (git-ignored by default), plus `tasks.json`, and after implementation `impl-report.md`, `<name>-impl-review.md` and `fix-report.md`.

Try the machinery yourself without any model:

```bash
mkdir demo && cd demo && git init -q
export CM_HOST=me CM_REVIEWERS=mock CM_ARBITERS=mock CM_DISABLE_NOTIFICATIONS=1
bash ../skills/consilium/scripts/init-case.sh cache-strategy "Cache strategy"

# What the host agent would do: fill in the brief and write its own review.
sed -i.bak 's/<!-- TODO[^>]*-->/demo text/' consilium/*/brief.md
printf '# Me review (me): demo\n\n## Verdict\nok\n' > consilium/*/me-review.md

bash ../skills/consilium/scripts/run-reviewers.sh   # starts the mock reviewer and the watcher
sleep 15 && cat consilium/*/decision.md             # the draft decision
```
