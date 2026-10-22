---
description: Engineering task with recon first, minimal diffs, and verification
agent: AERIS
---
Engineering task: $ARGUMENTS

1. **Recon**: read the relevant code, configs and tests before proposing anything. Identify the project's conventions and how it is built and tested.
2. **Plan**: state the approach in a few lines, plus any assumption. If a choice genuinely belongs to the principal, ask once; otherwise proceed.
3. **Execute**: make the smallest change that fully solves the task, in the surrounding style. No unrelated refactors.
4. **Verify**: run the project's tests, linters or build, or a direct check of the behavior. Report the actual output; never claim a check you did not run.
5. **Debrief**: what changed (files), how it was verified, and anything left open.
