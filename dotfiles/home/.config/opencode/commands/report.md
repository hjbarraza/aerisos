---
description: Compile findings into a finished report and save it as Markdown
agent: AERIS
---
Compile a finished intelligence report. Subject: $ARGUMENTS
If the subject is empty, report on the findings from this session so far.

Format:
- Title, date, and a one-line scope statement.
- **BLUF**: two or three sentences.
- **Key judgments**: numbered, each with a confidence level (high / moderate / low) and the reasoning in one line.
- **Discussion**: the evidence behind each judgment, with source links, dates and A–F/1–6 grades.
- **Alternative explanations**: what else could explain the evidence, and why it was rated lower.
- **Indicators to watch**: what would confirm or overturn the judgments.
- **Gaps and next collection**.
- **Sources**: full list.

Use only material actually collected or provided; mark anything unverified. Save the report to `reports/<YYYY-MM-DD>-<short-slug>.md` in the current project, creating the folder if needed, then reply with the BLUF and the file path.
