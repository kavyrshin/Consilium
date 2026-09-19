# Brief: {{TITLE}}

**Date:** {{DATE}}
**Format:** manual consilium (no coordinator).
**Roles this round:** {{ROLES}}

## Question

<!-- TODO: the question the user asked, tidied up but with its meaning intact -->

## Known facts and source references

<!-- TODO: facts only, no recommendations. Each with a reference: file:line, document, existing decision. -->

## Constraints

- Reviewers are read-only during analysis.
- Any destructive or production action, and any merge to the main branch, needs the user's explicit approval.
<!-- TODO: add 1-3 constraints specific to this question, if they are obvious -->

## Success criterion

The consilium is useful if, after the reviews, either (a) the approach proposed in the question is confirmed by the reviewers without changes, or (b) at least one review finds a concrete fact, risk or alternative that changes the decision. If no review adds anything beyond what is already known here, that is also a valid, though less valuable, outcome and is recorded in `decision.md` as it is.

## Out of scope

<!-- TODO: 1-3 items that this round deliberately does not address -->

## Response format

Each reviewer writes their own file in this folder (`<name>-review.md`) with exactly these sections:

```md
{{REVIEW_HEADINGS}}
```

Do not read other reviewers' files before your own is written. At most two rounds of discussion before `decision.md`.
