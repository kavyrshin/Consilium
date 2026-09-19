# English wording. Sourced by lib.sh when CM_LANG=en.
# To add a language: copy this file to <code>.sh, translate the values, copy
# templates/en to templates/<code>, translate it, and set CM_LANG=<code>.
# Keep the section headings stable: reviewers and arbiters are told to reproduce
# them verbatim, and the decision validator matches them exactly.

CM_LANG_NAME="English"
CM_L_REVIEW_WORD="review"

# Skeleton placeholders. cm_written() recognises the first words, keep them.
CM_L_REVIEW_PLACEHOLDER='> _Not filled in yet. Written independently by %s before reading the other reviews._'
CM_L_DECISION_PLACEHOLDER='> _Not filled in yet. The draft is synthesized by the arbiters; the final decision belongs to the human._'

# Review sections (also listed in the brief's response-format section).
CM_R1='## Verdict'
CM_R2='## Confirmed facts'
CM_R3='## Assumptions and unknowns'
CM_R4='## Risks and counter-arguments'
CM_R5='## Recommendation'
CM_R6='## What to check before implementing'

# Decision sections.
CM_D1='## Agreement'
CM_D2='## Disagreements'
CM_D3='## Decision'
CM_D4='## Minimal experiment that could refute the decision'
CM_D5='## Experiment results'
CM_D6='## Authorized code changes'
CM_D_NOT_RUN='_The experiment has not been run yet._'

# %s = arbiter label, model  (joint: label, model, label, model)
CM_L_DRAFT_SOLO='> **DRAFT - synthesized automatically by %s (%s); needs user confirmation before it is treated as the final decision.**'
CM_L_DRAFT_JOINT='> **DRAFT - synthesized jointly by %s (%s) + %s (%s); needs user confirmation before it is treated as the final decision.**'

# Panel note: written by the script from facts on disk, never by a model.
CM_L_NOTE_PREFIX='_Incomplete panel:'
CM_L_NOTE_MISSING='did not respond as reviewers: %s'
CM_L_NOTE_ARBITER='an arbiter did not take part in the synthesis (%s)'
CM_L_NOTE_TAIL='What the absent ones would have said is unknown and is not guessed here; the human arbiter weighs the gap._'

# Implementation verification report sections.
CM_V_TITLE='%s - implementation review (%s): %s'
CM_V1='## Verdict'
CM_V2='## What was actually changed'
CM_V3='## Defects'
CM_V4='## Instrumented checks (with numbers)'
CM_V5='## Still unverified'
CM_V_VERDICTS='accept / accept with remarks / send back for rework'

# Implementer report sections.
CM_I_TITLE='Implementer report (%s, %s): %s'
CM_I1='## What changed'
CM_I2='## What was checked'
CM_I3='## What was not done and why'
CM_I4='## What remains unverified'
CM_I_NOT_APPLIED='not applied'

# Roles line of the brief: reviewers, arbiters, implementer, verifiers.
CM_L_ROLES_FMT='Independent reviewers (read-only): %s. Draft decision synthesized by: %s. Implementation: %s. Verification: %s. The final arbiter is the human, not a model.'
CM_L_HOST_TAG='host'
CM_L_NONE='none available'

# Saved by the script when an agent answered on stdout instead of writing the file.
CM_L_STDOUT_NOTE='> _The answer arrived on stdout and was saved by the script (the agent did not use its write tool)._'
